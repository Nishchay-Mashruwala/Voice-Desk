//! Audio capture: microphone or system loopback -> 16 kHz mono 16-bit PCM,
//! either written to a WAV file or streamed live to a callback.
//!
//! cpal streams aren't `Send`, so each recording owns a dedicated thread that
//! builds the stream, keeps it alive until asked to stop, and handles samples.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc::{self, Receiver, Sender};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{FromSample, SampleFormat, SizedSample};

pub const TARGET_RATE: u32 = 16_000;
/// Live chunks are delivered every ~100 ms.
const CHUNK: usize = TARGET_RATE as usize / 10;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Source {
    Microphone,
    /// What's playing on the default output device — i.e. remote meeting participants.
    /// Windows: WASAPI loopback. macOS 14.6+: CoreAudio loopback (needs the
    /// "System Audio Recording" permission). Linux: PipeWire sink capture.
    System,
}

pub type ChunkFn = Box<dyn FnMut(&[i16]) + Send>;

pub enum Sink {
    File(PathBuf),
    /// Called with ~100 ms of 16 kHz samples at a time; optionally also saved to a WAV.
    Live(ChunkFn, Option<PathBuf>),
}

/// Streaming resampler to 16 kHz: windowed-sinc low-pass (so 8–24 kHz content
/// doesn't alias into the speech band) followed by linear interpolation.
struct Resampler {
    step: f64, // input samples per output sample
    taps: Vec<f32>,
    hist: Vec<f32>,
    pos: usize,
    prev: f32,
    n: u64,
    next_t: f64,
}

impl Resampler {
    fn new(in_rate: u32) -> Self {
        let step = in_rate as f64 / TARGET_RATE as f64;
        let taps = if step > 1.0 {
            // Cutoff at 7.2 kHz (normalised to the input rate), Blackman window.
            let n = 63;
            let fc = 7_200.0 / in_rate as f64;
            let m = (n - 1) as f64;
            let mut t: Vec<f32> = (0..n)
                .map(|i| {
                    let x = i as f64 - m / 2.0;
                    let sinc = if x == 0.0 { 2.0 * fc } else { (2.0 * std::f64::consts::PI * fc * x).sin() / (std::f64::consts::PI * x) };
                    let w = 0.42 - 0.5 * (2.0 * std::f64::consts::PI * i as f64 / m).cos()
                        + 0.08 * (4.0 * std::f64::consts::PI * i as f64 / m).cos();
                    (sinc * w) as f32
                })
                .collect();
            let sum: f32 = t.iter().sum();
            t.iter_mut().for_each(|v| *v /= sum);
            t
        } else {
            vec![1.0]
        };
        let len = taps.len();
        Self { step, taps, hist: vec![0.0; len], pos: 0, prev: 0.0, n: 0, next_t: 0.0 }
    }

    fn push(&mut self, x: f32, out: &mut Vec<f32>) {
        let len = self.hist.len();
        self.hist[self.pos] = x;
        self.pos = (self.pos + 1) % len;
        // Convolve: taps[0] pairs with the oldest sample.
        let mut y = 0.0f32;
        for (k, tap) in self.taps.iter().enumerate() {
            y += tap * self.hist[(self.pos + k) % len];
        }
        let n = self.n as f64;
        while self.next_t <= n {
            let frac = (self.next_t - (n - 1.0)) as f32;
            out.push(self.prev + (y - self.prev) * frac);
            self.next_t += self.step;
        }
        self.prev = y;
        self.n += 1;
    }
}

enum Msg {
    Samples(Vec<f32>),
    Stop,
}

pub struct Recording {
    tx: Sender<Msg>,
    thread: Option<JoinHandle<Result<()>>>,
    /// Live input level (RMS * 1000) for the UI meters.
    level: Arc<AtomicU32>,
}

impl Recording {
    pub fn start(source: Source, sink: Sink) -> Result<Self> {
        let (tx, rx) = mpsc::channel::<Msg>();
        let (ready_tx, ready_rx) = mpsc::channel::<Result<()>>();
        let level = Arc::new(AtomicU32::new(0));
        let tx_cb = tx.clone();
        let level_cb = level.clone();

        let thread = std::thread::Builder::new()
            .name(format!("record-{source:?}"))
            .spawn(move || record_thread(source, sink, tx_cb, rx, level_cb, ready_tx))?;

        // Surface device errors to the caller instead of failing silently in the thread.
        match ready_rx.recv_timeout(Duration::from_secs(5)) {
            Ok(Ok(())) => {}
            Ok(Err(e)) => {
                let _ = thread.join();
                return Err(e);
            }
            Err(_) => {
                // It may still open later: tell its thread to close it right away.
                let _ = tx.send(Msg::Stop);
                return Err(anyhow!("audio device did not start in time"));
            }
        }
        Ok(Self { tx, thread: Some(thread), level })
    }

    pub fn to_file(source: Source, path: &Path) -> Result<Self> {
        Self::start(source, Sink::File(path.to_path_buf()))
    }

    pub fn level(&self) -> f32 {
        self.level.load(Ordering::Relaxed) as f32 / 1000.0
    }

    /// Stop recording; flushes remaining samples and finalizes the WAV.
    pub fn stop(mut self) -> Result<()> {
        let _ = self.tx.send(Msg::Stop);
        if let Some(t) = self.thread.take() {
            t.join().map_err(|_| anyhow!("recording thread panicked"))??;
        }
        Ok(())
    }
}

impl Drop for Recording {
    fn drop(&mut self) {
        let _ = self.tx.send(Msg::Stop);
    }
}

type Wav = hound::WavWriter<std::io::BufWriter<std::fs::File>>;

enum Out {
    Wav(Wav),
    Live(ChunkFn, Vec<i16>, Option<Wav>),
}

fn wav_writer(path: &Path) -> Result<Wav> {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate: TARGET_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    hound::WavWriter::create(path, spec).with_context(|| format!("could not create {}", path.display()))
}

impl Out {
    fn write(&mut self, samples: &[i16]) -> Result<()> {
        match self {
            Out::Wav(w) => {
                for &s in samples {
                    w.write_sample(s)?;
                }
            }
            Out::Live(cb, buf, file) => {
                if let Some(w) = file {
                    for &s in samples {
                        w.write_sample(s)?;
                    }
                }
                buf.extend_from_slice(samples);
                if buf.len() >= CHUNK {
                    cb(buf);
                    buf.clear();
                }
            }
        }
        Ok(())
    }

    fn finish(self) -> Result<()> {
        match self {
            Out::Wav(w) => w.finalize()?,
            Out::Live(mut cb, buf, file) => {
                if !buf.is_empty() {
                    cb(&buf);
                }
                if let Some(w) = file {
                    w.finalize()?;
                }
            }
        }
        Ok(())
    }
}

/// A recording saved as `path` (.wav while recording), or its compressed
/// .flac once processed. None if neither exists (deleted or expired).
pub fn recorded(path: &Path) -> Option<PathBuf> {
    let flac = path.with_extension("flac");
    [path.to_path_buf(), flac].into_iter().find(|p| p.exists())
}

/// Delete a recording in whichever format it's in.
pub fn remove_recording(path: &Path) {
    let _ = std::fs::remove_file(path.with_extension("wav"));
    let _ = std::fs::remove_file(path.with_extension("flac"));
}

fn record_thread(
    source: Source,
    sink: Sink,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    level: Arc<AtomicU32>,
    ready: Sender<Result<()>>,
) -> Result<()> {
    let setup = || -> Result<(cpal::Stream, u32)> {
        let host = cpal::default_host();
        let (device, config) = match source {
            Source::Microphone => {
                let d = host.default_input_device().context("no microphone found")?;
                let c = d.default_input_config()?;
                (d, c)
            }
            Source::System => {
                // On every supported backend, an input stream opened on an output
                // device captures what that device is playing (loopback).
                let d = host.default_output_device().context("no output device found")?;
                let c = d.default_output_config()?;
                (d, c)
            }
        };
        let rate = config.sample_rate();
        let channels = config.channels() as usize;
        let stream = match config.sample_format() {
            SampleFormat::F32 => build::<f32>(&device, config.into(), channels, tx.clone(), level.clone())?,
            SampleFormat::I16 => build::<i16>(&device, config.into(), channels, tx.clone(), level.clone())?,
            SampleFormat::I32 => build::<i32>(&device, config.into(), channels, tx.clone(), level.clone())?,
            SampleFormat::U16 => build::<u16>(&device, config.into(), channels, tx.clone(), level.clone())?,
            f => return Err(anyhow!("unsupported sample format {f}")),
        };
        stream.play()?;
        Ok((stream, rate))
    };

    let (stream, in_rate) = match setup() {
        Ok(v) => v,
        Err(e) => {
            let _ = ready.send(Err(anyhow!("{source:?}: {e}")));
            return Ok(());
        }
    };

    let out = match sink {
        Sink::File(path) => wav_writer(&path).map(Out::Wav),
        Sink::Live(cb, path) => path
            .map(|p| wav_writer(&p))
            .transpose()
            .map(|file| Out::Live(cb, Vec::with_capacity(CHUNK * 2), file)),
    };
    let mut out = match out {
        Ok(o) => o,
        Err(e) => {
            let _ = ready.send(Err(e));
            return Ok(());
        }
    };
    let _ = ready.send(Ok(()));

    let mut rs = Resampler::new(in_rate);
    let mut resampled = Vec::with_capacity(4096);
    let mut pcm = Vec::with_capacity(4096);

    // Loopback delivers no packets while nothing is playing, so pad with silence
    // to keep the system track time-aligned with the microphone track.
    let started = std::time::Instant::now();
    let mut written: u64 = 0;

    loop {
        match rx.recv_timeout(Duration::from_millis(100)) {
            Ok(Msg::Samples(buf)) => {
                resampled.clear();
                for s in buf {
                    rs.push(s, &mut resampled);
                }
                pcm.clear();
                pcm.extend(resampled.iter().map(|&s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16));
                out.write(&pcm)?;
                written += pcm.len() as u64;
            }
            Ok(Msg::Stop) | Err(mpsc::RecvTimeoutError::Disconnected) => break,
            Err(mpsc::RecvTimeoutError::Timeout) => {}
        }
        if source == Source::System {
            let expected = (started.elapsed().as_secs_f64() * TARGET_RATE as f64) as u64;
            // Only pad real gaps (>0.5s) so normal packet jitter doesn't add silence.
            if expected > written + TARGET_RATE as u64 / 2 {
                let gap = vec![0i16; (expected - written) as usize];
                out.write(&gap)?;
                written = expected;
            }
        }
    }
    drop(stream);
    // Samples still queued after Stop belong to what the user said last.
    while let Ok(Msg::Samples(buf)) = rx.try_recv() {
        resampled.clear();
        for s in buf {
            rs.push(s, &mut resampled);
        }
        pcm.clear();
        pcm.extend(resampled.iter().map(|&s| (s.clamp(-1.0, 1.0) * i16::MAX as f32) as i16));
        out.write(&pcm)?;
    }
    out.finish()
}

fn build<T>(
    device: &cpal::Device,
    config: cpal::StreamConfig,
    channels: usize,
    tx: Sender<Msg>,
    level: Arc<AtomicU32>,
) -> Result<cpal::Stream>
where
    T: SizedSample,
    f32: FromSample<T>,
{
    let stream = device.build_input_stream::<T, _, _>(
        config,
        move |data: &[T], _| {
            let mut mono = Vec::with_capacity(data.len() / channels.max(1));
            let mut sq = 0.0f32;
            for frame in data.chunks(channels.max(1)) {
                let s = frame.iter().map(|&x| x.to_sample::<f32>()).sum::<f32>() / frame.len() as f32;
                sq += s * s;
                mono.push(s);
            }
            if !mono.is_empty() {
                let rms = (sq / mono.len() as f32).sqrt();
                level.store((rms * 1000.0) as u32, Ordering::Relaxed);
            }
            let _ = tx.send(Msg::Samples(mono));
        },
        |err| eprintln!("[audio] stream error: {err}"),
        None,
    )?;
    Ok(stream)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tone(freq: f64, rate: u32, secs: f64) -> Vec<f32> {
        (0..(rate as f64 * secs) as usize)
            .map(|i| (2.0 * std::f64::consts::PI * freq * i as f64 / rate as f64).sin() as f32 * 0.5)
            .collect()
    }

    fn rms_out(input: &[f32], rate: u32) -> (usize, f32) {
        let mut rs = Resampler::new(rate);
        let mut out = Vec::new();
        for &s in input {
            rs.push(s, &mut out);
        }
        let tail = &out[out.len() / 4..]; // skip filter warm-up
        (out.len(), (tail.iter().map(|x| x * x).sum::<f32>() / tail.len() as f32).sqrt())
    }

    #[test]
    fn keeps_speech_band_and_rate() {
        for rate in [44_100, 48_000] {
            let (n, rms) = rms_out(&tone(1_000.0, rate, 1.0), rate);
            assert!((n as i64 - 16_000).abs() <= 2, "{rate}: got {n} samples");
            assert!((rms - 0.354).abs() < 0.02, "{rate}: 1 kHz tone rms {rms}");
        }
    }

    #[test]
    fn blocks_aliasing() {
        // 12 kHz would alias to 4 kHz at 16 kHz without the low-pass filter.
        let (_, rms) = rms_out(&tone(12_000.0, 48_000, 1.0), 48_000);
        assert!(rms < 0.01, "12 kHz leaked through: rms {rms}");
    }

    #[test]
    fn finds_a_recording_in_either_format() {
        let dir = std::env::temp_dir().join(format!("vd-rec-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("meeting-1-mic.wav");
        assert_eq!(recorded(&wav), None);
        std::fs::write(dir.join("meeting-1-mic.flac"), b"fLaC").unwrap();
        assert_eq!(recorded(&wav), Some(dir.join("meeting-1-mic.flac")));
        std::fs::write(&wav, b"RIFF").unwrap(); // still being recorded: the WAV wins
        assert_eq!(recorded(&wav), Some(wav.clone()));
        remove_recording(&wav);
        assert_eq!(recorded(&wav), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn passthrough_at_16k() {
        let (n, rms) = rms_out(&tone(1_000.0, 16_000, 1.0), 16_000);
        assert_eq!(n, 16_000);
        assert!((rms - 0.354).abs() < 0.01);
    }
}
