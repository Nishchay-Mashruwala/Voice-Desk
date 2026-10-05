//! Meetings: recording (from the Meetings page, the call offer or the
//! shortcut), processing, playback audio, and converting to/from Listen recordings.

use std::time::Instant;

use serde::Serialize;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, State};

use crate::{err, CmdResult, Shared};
use crate::audio::{self, Recording, Source};
use crate::db::{Dictation, Meeting, Segment};
use crate::{pipeline, session};

pub struct ActiveMeeting {
    pub id: i64,
    pub(crate) mic: Recording,
    pub(crate) system: Option<Recording>,
    /// Where the meeting's clock starts: when listening started, if it took over.
    pub started: Instant,
    /// When each track's recording began, to line the takeover up with them.
    mic_at: Instant,
    system_at: Option<Instant>,
    /// Listening that was going on when the meeting started: joined in front.
    hand_over: Option<session::HandOver>,
    /// The call app it was started during (auto-stop when that app releases the mic).
    pub call_key: Option<String>,
}

impl ActiveMeeting {
    /// Stop both tracks (both, even if the first fails), then join the
    /// listening it took over in front of them. Also used when quitting.
    pub(crate) fn finish(self, mic_path: &std::path::Path, sys_path: &std::path::Path) -> anyhow::Result<()> {
        let mic = self.mic.stop();
        let system = self.system.map(|s| s.stop()).unwrap_or(Ok(()));
        let stopped = mic.and(system);
        if let (Ok(()), Some(h)) = (&stopped, &self.hand_over) {
            // Not fatal: the meeting is still there without its beginning.
            match join_hand_over(h, mic_path, self.mic_at, sys_path, self.system_at) {
                Ok(()) => audio::remove_recording(&h.audio),
                Err(e) => eprintln!("[meeting] couldn't join the listening before it: {e}"),
            }
        }
        stopped
    }
}

#[derive(Serialize)]
pub struct StartedMeeting {
    pub id: i64,
    pub system_audio: bool,
    pub warning: Option<String>,
}

/// Async so opening the audio devices doesn't hold up the windows (a plain
/// command runs on the main thread).
#[tauri::command]
pub async fn start_meeting(app: AppHandle, st: State<'_, Shared>, title: String) -> CmdResult<StartedMeeting> {
    begin_meeting(&app, st.inner(), &title)
}

/// Start recording a meeting: the mic (you) and the speakers (everyone else).
pub(crate) fn begin_meeting(app: &AppHandle, st: &Shared, title: &str) -> CmdResult<StartedMeeting> {
    let started = begin_meeting_inner(app, st, title);
    *st.call_prompt.lock().unwrap() = None;
    session::emit_status(app, st);
    started
}

const ALREADY_RECORDING: &str = "A meeting is already being recorded";

/// The devices open without holding the `meeting` lock (opening can take
/// seconds; the meters, the status and the call watcher read it meanwhile).
/// The lock is taken only to check, and at the end to store the recording.
fn begin_meeting_inner(app: &AppHandle, st: &Shared, title: &str) -> CmdResult<StartedMeeting> {
    if st.meeting.lock().unwrap().is_some() {
        return Err(ALREADY_RECORDING.into());
    }
    let title = if title.trim().is_empty() {
        format!("Meeting {}", chrono::Local::now().format("%b %d, %H:%M"))
    } else {
        title.trim().to_string()
    };
    let id = st.db.create_meeting(&title, "meeting").map_err(err)?;
    let (mic_path, sys_path) = st.meeting_paths(id);

    let mic = match Recording::to_file(Source::Microphone, &mic_path) {
        Ok(r) => r,
        Err(e) => {
            let _ = st.db.set_meeting_status(id, "error", Some(&e.to_string()));
            let _ = app.emit("meetings-changed", ());
            return Err(format!("Microphone error: {e}"));
        }
    };
    let mic_at = Instant::now();
    let (system, warning) = match Recording::to_file(Source::System, &sys_path) {
        Ok(r) => (Some(r), None),
        Err(e) => (None, Some(format!("System audio unavailable, recording microphone only: {e}"))),
    };
    let system_at = system.is_some().then(Instant::now);
    let system_audio = system.is_some();
    let call_key = st.call.lock().unwrap().as_ref().map(|c| c.key.clone());
    let mut slot = st.meeting.lock().unwrap();
    if slot.is_some() {
        // Another start won while these devices opened: drop this one entirely.
        drop(slot);
        let _ = mic.stop();
        if let Some(s) = system {
            let _ = s.stop();
        }
        audio::remove_recording(&mic_path);
        audio::remove_recording(&sys_path);
        let _ = st.db.delete_meeting(id);
        return Err(ALREADY_RECORDING.into());
    }
    *slot = Some(ActiveMeeting { id, mic, system, started: mic_at, mic_at, system_at, hand_over: None, call_key });
    drop(slot);
    // Listening already? It becomes the start of this meeting (both recorded the
    // mic for a moment, so nothing is missed; the overlap is cut when joining).
    if let Some(h) = session::hand_over(app, st) {
        if let Some(m) = st.meeting.lock().unwrap().as_mut().filter(|m| m.id == id) {
            m.started = h.started;
            m.hand_over = Some(h);
        }
    }
    let _ = app.emit("meetings-changed", ());
    Ok(StartedMeeting { id, system_audio, warning })
}

#[tauri::command]
pub async fn stop_meeting(app: AppHandle, st: State<'_, Shared>) -> CmdResult<i64> {
    end_meeting(&app, st.inner()).await
}

/// Stop recording the meeting, then transcribe it and find tasks in the background.
pub(crate) async fn end_meeting(app: &AppHandle, st: &Shared) -> CmdResult<i64> {
    let active = st.meeting.lock().unwrap().take().ok_or("No meeting is being recorded")?;
    session::emit_status(app, st);
    let _ = app.emit("meetings-changed", ());
    let id = active.id;
    let (mic_path, sys_path) = st.meeting_paths(id);
    let stopped = tauri::async_runtime::spawn_blocking(move || active.finish(&mic_path, &sys_path))
    .await
    .map_err(err)
    .and_then(|r| r.map_err(err));
    if let Err(e) = stopped {
        // Not left "recording" forever: the meeting shows what went wrong.
        let _ = st.db.set_meeting_status(id, "error", Some(&format!("The recording couldn't be saved: {e}")));
        let _ = app.emit("meetings-changed", ());
        return Err(e);
    }
    let (app, st) = (app.clone(), st.clone());
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st, id, pipeline::Input::Recording).await;
    });
    Ok(id)
}

/// Samples (16 kHz) from `from` to `to`; negative when `to` is earlier.
fn samples_between(from: Instant, to: Instant) -> i64 {
    let secs = match to.checked_duration_since(from) {
        Some(d) => d.as_secs_f64(),
        None => -from.duration_since(to).as_secs_f64(),
    };
    (secs * audio::TARGET_RATE as f64).round() as i64
}

/// What goes in front of a track that started `offset` samples after the
/// listening recording (`listen`, which may have kept going a moment longer)
/// ended: the listening up to that track's start, or with silence for a gap.
fn lead_in(listen: &[i16], offset: i64) -> Vec<i16> {
    let n = (listen.len() as i64 + offset).max(0) as usize;
    let mut out = listen[..n.min(listen.len())].to_vec();
    out.resize(n, 0);
    out
}

/// Write `lead` in front of a finished WAV (streamed: an hour is ~115 MB).
fn prepend(path: &std::path::Path, lead: &[i16]) -> anyhow::Result<()> {
    let reader = hound::WavReader::open(path)?;
    let spec = reader.spec();
    let tmp = path.with_extension("joining.wav");
    {
        let mut w = hound::WavWriter::create(&tmp, spec)?;
        for &s in lead {
            w.write_sample(s)?;
        }
        for s in reader.into_samples::<i16>() {
            w.write_sample(s?)?;
        }
        w.finalize()?;
    }
    std::fs::rename(&tmp, path)?;
    Ok(())
}

/// The listening that a meeting took over, joined in front of the meeting's
/// tracks: the mic track gets the listening (the moment both recorded is cut),
/// the computer-audio track the same length of silence, so the two stay in step.
pub(crate) fn join_hand_over(
    h: &session::HandOver,
    mic: &std::path::Path,
    mic_at: Instant,
    system: &std::path::Path,
    system_at: Option<Instant>,
) -> anyhow::Result<()> {
    let listen: Vec<i16> = hound::WavReader::open(&h.audio)?.into_samples::<i16>().collect::<Result<_, _>>()?;
    prepend(mic, &lead_in(&listen, samples_between(h.stopped, mic_at)))?;
    if let Some(at) = system_at.filter(|_| system.exists()) {
        let n = lead_in(&listen, samples_between(h.stopped, at)).len();
        prepend(system, &vec![0; n])?;
    }
    Ok(())
}

#[tauri::command]
pub fn active_meeting(st: State<Shared>) -> Option<Value> {
    st.meeting.lock().unwrap().as_ref().map(|m| json!({ "id": m.id, "elapsed_s": m.started.elapsed().as_secs_f64() }))
}

/// "Transcribe Meeting" on the overlay's call offer.
#[tauri::command]
pub async fn call_prompt_accept(app: AppHandle, st: State<'_, Shared>) -> CmdResult<()> {
    accept_call(&app, st.inner())
}

/// Record the call the overlay is offering (its button, or the shortcut).
pub(crate) fn accept_call(app: &AppHandle, st: &Shared) -> CmdResult<()> {
    let call = st.call_prompt.lock().unwrap().clone().ok_or("The call has ended")?;
    // Listening, if on, becomes the start of the meeting (`begin_meeting_inner`).
    let title = format!("{} call · {}", call.app, chrono::Local::now().format("%b %d, %H:%M"));
    let started = begin_meeting(app, st, &title)?;
    let message = started.warning.unwrap_or_else(|| format!("Recording the {} call", call.app));
    let _ = app.emit("session-notice", json!({ "message": message, "short": "● Recording" }));
    Ok(())
}

/// ✕ on the call offer: not for this call.
#[tauri::command]
pub fn call_prompt_dismiss(app: AppHandle, st: State<Shared>) {
    if let Some(call) = st.call_prompt.lock().unwrap().take() {
        *st.call_dismiss.lock().unwrap() = Some(call.key);
    }
    session::emit_status(&app, st.inner());
}

/// Re-run the pipeline. `transcribe = false` only re-extracts tasks (e.g. after changing your name).
#[tauri::command]
pub fn reprocess_meeting(app: AppHandle, st: State<Shared>, id: i64, transcribe: bool) -> CmdResult<()> {
    let input = if transcribe {
        let (mic, sys) = st.meeting_paths(id);
        if audio::recorded(&mic).is_none() && audio::recorded(&sys).is_none() {
            return Err("The audio for this recording is no longer available".into());
        }
        pipeline::Input::Recording
    } else {
        pipeline::Input::Reextract
    };
    let st = st.inner().clone();
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st, id, input).await;
    });
    Ok(())
}

/// One of a meeting's two recordings: "mic" (you) or "system" (the computer's audio).
/// Read off the main thread: an hour-long track is ~100 MB as WAV.
#[tauri::command]
pub async fn meeting_audio(st: State<'_, Shared>, id: i64, track: String) -> CmdResult<tauri::ipc::Response> {
    let (mic, system) = st.meeting_paths(id);
    let path = audio::recorded(if track == "system" { &system } else { &mic }).ok_or("This recording is not available")?;
    let bytes = tauri::async_runtime::spawn_blocking(move || std::fs::read(&path))
        .await
        .map_err(err)?
        .map_err(|_| "This recording is not available".to_string())?;
    Ok(tauri::ipc::Response::new(bytes))
}

#[derive(Serialize)]
pub struct MeetingTracks {
    pub mic: bool,
    pub system: bool,
}

#[tauri::command]
pub fn meeting_tracks(st: State<Shared>, id: i64) -> MeetingTracks {
    let (mic, system) = st.meeting_paths(id);
    MeetingTracks { mic: audio::recorded(&mic).is_some(), system: audio::recorded(&system).is_some() }
}

/// Find tasks in a Listen recording. The tasks are grouped under a hidden
/// "dictation" entry so they show where they came from on the Tasks page.
#[tauri::command]
pub async fn dictation_find_tasks(app: AppHandle, st: State<'_, Shared>, id: i64) -> CmdResult<usize> {
    let d = st.db.dictation(id).map_err(err)?.ok_or("Recording not found")?;
    let when = chrono::DateTime::parse_from_rfc3339(&d.created_at)
        .map(|t| t.format("%b %d, %H:%M").to_string())
        .unwrap_or_default();
    // Tasks already found: don't add the same ones again. If they were all
    // deleted, look again into the same meeting rather than a new one.
    if !d.tasks.is_empty() {
        return Ok(d.tasks.len());
    }
    let meeting_id = match d.meeting_id {
        Some(m) => m,
        None => {
            let m = st.db.create_meeting(&format!("Recording · {when}"), "dictation").map_err(err)?;
            st.db.set_dictation_meeting(id, m).map_err(err)?;
            m
        }
    };
    let duration = d.duration_ms as f64 / 1000.0;
    let words = serde_json::from_value(d.words).ok();
    let segment = Segment { start: 0.0, end: duration, speaker: "Me".into(), text: d.text, words };
    st.db.save_transcript(meeting_id, &[segment], duration).map_err(err)?;
    pipeline::process(app, st.inner().clone(), meeting_id, pipeline::Input::Reextract).await
}

/// "Make it a meeting": re-transcribe a Listen recording with speaker detection.
/// (Async: moving the recording can mean copying it.)
#[tauri::command]
pub async fn dictation_to_meeting(app: AppHandle, st: State<'_, Shared>, id: i64) -> CmdResult<i64> {
    let d = st.db.dictation(id).map_err(err)?.ok_or("Recording not found")?;
    if !d.has_audio {
        return Err("This recording's audio was already deleted, so it can't be transcribed again".into());
    }
    let when = chrono::DateTime::parse_from_rfc3339(&d.created_at)
        .map(|t| t.format("%b %d, %H:%M").to_string())
        .unwrap_or_default();
    let (meeting_id, audio) = st.db.dictation_into_meeting(id, &format!("Meeting · {when}")).map_err(err)?;
    let (mic, sys) = st.meeting_paths(meeting_id);
    audio::remove_recording(&sys);
    if let Some(audio) = audio {
        // Keep the format it's in (WAV, or FLAC once compressed).
        let ext = std::path::Path::new(&audio).extension().and_then(|e| e.to_str()).unwrap_or("wav").to_string();
        let mic = mic.with_extension(ext);
        if std::fs::rename(&audio, &mic).is_err() {
            std::fs::copy(&audio, &mic).map_err(|e| format!("Couldn't move the recording: {e}"))?;
            let _ = std::fs::remove_file(&audio);
        }
    }
    let _ = app.emit("meetings-changed", ());
    let _ = app.emit("tasks-changed", ());
    let st2 = st.inner().clone();
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st2, meeting_id, pipeline::Input::Recording).await;
    });
    Ok(meeting_id)
}

/// "Move to Listen history": one recording (both tracks mixed), words from the transcript.
#[tauri::command]
pub async fn meeting_to_dictation(app: AppHandle, st: State<'_, Shared>, id: i64) -> CmdResult<Dictation> {
    let m = st.db.meeting(id).map_err(err)?.ok_or("Meeting not found")?;
    if !matches!(m.status.as_str(), "done" | "error") {
        return Err("Wait until the meeting has finished processing".into());
    }
    let segments = st.db.transcript(id).map_err(err)?;
    let mut words: Vec<Value> = Vec::new();
    for s in &segments {
        match &s.words {
            Some(ws) if !ws.is_empty() => words.extend(ws.iter().map(|w| json!({ "w": w.w, "s": w.s, "e": w.e }))),
            // Older transcripts: spread the line's time over its words.
            _ => {
                let parts: Vec<&str> = s.text.split_whitespace().collect();
                let total: usize = parts.iter().map(|p| p.chars().count() + 1).sum::<usize>().max(1);
                let mut t = s.start;
                for p in parts {
                    let d = (s.end - s.start) * (p.chars().count() + 1) as f64 / total as f64;
                    words.push(json!({ "w": p, "s": t, "e": t + d }));
                    t += d;
                }
            }
        }
    }
    let text = segments.iter().map(|s| s.text.trim()).collect::<Vec<_>>().join(" ");

    let (mic, sys) = st.meeting_paths(id);
    let tracks: Vec<std::path::PathBuf> = [audio::recorded(&mic), audio::recorded(&sys)].into_iter().flatten().collect();
    let audio = if tracks.is_empty() {
        None
    } else {
        // The engine mixes both tracks into one FLAC.
        let out = st
            .recordings_dir()
            .join(format!("listen-{}-m{id}.flac", chrono::Local::now().format("%Y%m%d-%H%M%S")));
        st.engine.request("mix", json!({ "paths": tracks, "out": out }), None).await.map_err(err)?;
        Some(out)
    };
    let duration_ms = (m.duration_s.unwrap_or(0.0) * 1000.0) as i64;
    let did = match st.db.meeting_into_dictation(id, &text, duration_ms, audio.as_deref(), &Value::Array(words)) {
        Ok(did) => did,
        Err(e) => {
            if let Some(a) = &audio {
                let _ = std::fs::remove_file(a);
            }
            return Err(err(e));
        }
    };
    audio::remove_recording(&mic);
    audio::remove_recording(&sys);
    let d = st.db.dictation(did).map_err(err)?.ok_or("Recording not found")?;
    let _ = app.emit("meetings-changed", ());
    let _ = app.emit("tasks-changed", ());
    Ok(d)
}

#[tauri::command]
pub async fn list_meetings(st: State<'_, Shared>) -> CmdResult<Vec<Meeting>> {
    st.db.meetings().map_err(err)
}

/// Async: a long meeting's transcript (with word timings) is several MB of JSON.
#[tauri::command]
pub async fn get_transcript(st: State<'_, Shared>, id: i64) -> CmdResult<Vec<Segment>> {
    st.db.transcript(id).map_err(err)
}

#[tauri::command]
pub fn rename_meeting(st: State<Shared>, id: i64, title: String) -> CmdResult<()> {
    st.db.rename_meeting(id, &title).map_err(err)
}

#[tauri::command]
pub fn delete_meeting(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<()> {
    if st.meeting.lock().unwrap().as_ref().map(|m| m.id) == Some(id) {
        return Err("Stop the recording first".into());
    }
    let (mic, sys) = st.meeting_paths(id);
    audio::remove_recording(&mic);
    audio::remove_recording(&sys);
    st.db.delete_meeting(id).map_err(err)?;
    // Its tasks went with it.
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

/// Rename a speaker in a meeting; with `remember`, their voice is recognised
/// (and named) in later meetings.
#[tauri::command]
pub async fn rename_speaker(app: AppHandle, st: State<'_, Shared>, meeting_id: i64, from: String, to: String, remember: bool) -> CmdResult<()> {
    let to = to.trim().to_string();
    if to.is_empty() || to == "Me" {
        return Err("Type a name".into());
    }
    if remember {
        let spans: Vec<[f64; 2]> =
            st.db.transcript(meeting_id).map_err(err)?.iter().filter(|s| s.speaker == from).map(|s| [s.start, s.end]).collect();
        // Their voice is on the computer audio in a call, or on the mic in person.
        let (mic, sys) = st.meeting_paths(meeting_id);
        let track = audio::recorded(&sys).or_else(|| audio::recorded(&mic)).ok_or("The audio for this meeting is no longer available")?;
        let r = st.engine.request("speaker_voice", json!({ "path": track, "spans": spans }), None).await.map_err(err)?;
        let emb: Vec<f32> = serde_json::from_value(r["embedding"].clone()).map_err(err)?;
        st.db.remember_voice(&to, &emb).map_err(err)?;
    }
    st.db.rename_speaker(meeting_id, &from, &to).map_err(err)?;
    let _ = app.emit("meetings-changed", ());
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

/// Fix a transcript line (misheard words). `words`: the line's words with times.
#[tauri::command]
pub fn update_transcript_line(app: AppHandle, st: State<Shared>, meeting_id: i64, index: usize, text: String, words: Vec<crate::db::Word>) -> CmdResult<()> {
    st.db.update_transcript_line(meeting_id, index, text.trim(), words).map_err(err)?;
    let _ = app.emit("meetings-changed", ());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn listening_is_cut_where_the_meeting_track_began() {
        let listen: Vec<i16> = (1..=10).collect();
        // The meeting's track started 3 samples before listening stopped: drop the overlap.
        assert_eq!(lead_in(&listen, -3), vec![1, 2, 3, 4, 5, 6, 7]);
        // It started 2 samples after: silence fills the gap.
        assert_eq!(lead_in(&listen, 2), vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 0, 0]);
        assert_eq!(lead_in(&listen, -20), Vec::<i16>::new());
    }

    #[test]
    fn samples_between_instants_either_way() {
        let t = Instant::now();
        assert_eq!(samples_between(t, t + Duration::from_millis(250)), 4000);
        assert_eq!(samples_between(t + Duration::from_millis(250), t), -4000);
    }

    #[test]
    fn handed_over_listening_starts_both_tracks_in_step() {
        let dir = std::env::temp_dir().join(format!("vd-handover-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let spec = hound::WavSpec { channels: 1, sample_rate: 16_000, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let write = |name: &str, samples: &[i16]| {
            let p = dir.join(name);
            let mut w = hound::WavWriter::create(&p, spec).unwrap();
            for &s in samples {
                w.write_sample(s).unwrap();
            }
            w.finalize().unwrap();
            p
        };
        let read = |p: &std::path::Path| hound::WavReader::open(p).unwrap().into_samples::<i16>().map(|s| s.unwrap()).collect::<Vec<_>>();
        let listen = write("listen.wav", &[7; 16_000]); // 1 s of listening
        let mic = write("mic.wav", &[5; 100]);
        let system = write("system.wav", &[3; 100]);

        let stopped = Instant::now();
        // Meeting mic opened 0.5 s before listening stopped, system audio 0.25 s before.
        let mic_at = stopped - Duration::from_millis(500);
        let system_at = stopped - Duration::from_millis(250);
        let h = session::HandOver { audio: listen, started: stopped, stopped };
        join_hand_over(&h, &mic, mic_at, &system, Some(system_at)).unwrap();

        let (m, s) = (read(&mic), read(&system));
        assert_eq!(m.len(), 8_000 + 100); // listening up to the meeting mic's start, then the meeting
        assert!(m[..8_000].iter().all(|&x| x == 7) && m[8_000..].iter().all(|&x| x == 5));
        assert_eq!(s.len(), 12_000 + 100); // silence up to the system track's start
        assert!(s[..12_000].iter().all(|&x| x == 0) && s[12_000..].iter().all(|&x| x == 3));
        // Both tracks now begin at the moment listening's recording began.
        assert_eq!(m.len() as i64 - 100 - 8_000, s.len() as i64 - 100 - 12_000);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
