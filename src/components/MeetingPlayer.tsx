import { memo, useEffect, useMemo, useRef, useState } from "react";
import { api, formatDuration, type Segment, type SourceFocus, type Word } from "../api";
import { Pause, Play } from "../icons";
import { quoteStart, taskOfWords, type TaskMark } from "../taskMarks";
import { toast } from "../toast";

type Track = "mic" | "system";
const TRACK_LABEL: Record<Track, string> = { mic: "You (microphone)", system: "Others (computer audio)" };

/** Older transcripts have no word timings: spread the line's time over its words by length. */
function spreadWords(s: Segment): Word[] {
  const parts = s.text.split(/\s+/).filter(Boolean);
  const total = parts.reduce((n, w) => n + w.length + 1, 0) || 1;
  let t = s.start;
  return parts.map((w) => {
    const d = ((s.end - s.start) * (w.length + 1)) / total;
    const word = { w, s: t, e: t + d };
    t += d;
    return word;
  });
}

type LineState = "" | "now" | "spoken" | "upcoming";

/**
 * One transcript line. Memoised: while playing, only the current line gets a
 * new `time` (the others get a fixed one), so an hour-long meeting doesn't
 * redraw thousands of words every frame.
 */
const Line = memo(function Line({
  seg,
  index,
  words,
  taskOf,
  state,
  time,
  onSeek,
}: {
  seg: Segment;
  index: number;
  words: Word[];
  taskOf: (string | null)[];
  state: LineState;
  time: number;
  onSeek: (t: number) => void;
}) {
  return (
    <div data-seg={index} className={`seg ${seg.speaker === "Me" ? "me" : ""} ${state}`} onClick={() => onSeek(seg.start)}>
      <span className="seg-time">{formatDuration(seg.start)}</span>
      <span className="seg-speaker">{seg.speaker}</span>
      <span className={`seg-text karaoke ${state === "now" || state === "spoken" ? "" : "idle"}`}>
        {words.map((w, i) => {
          const ws = state === "now" ? (time >= w.e ? "spoken" : time >= w.s ? "now" : "") : state === "spoken" ? "spoken" : "";
          return (
            <span key={i}>
              <span
                className={`w ${ws} ${taskOf[i] ? "task-word" : ""}`}
                title={taskOf[i] ? `Task: ${taskOf[i]}` : undefined}
                onClick={(e) => {
                  e.stopPropagation();
                  onSeek(w.s);
                }}
              >
                {w.w}
              </span>{" "}
            </span>
          );
        })}
      </span>
    </div>
  );
});

/**
 * Plays a meeting's two recordings together — your microphone and the
 * computer's audio — with the transcript underneath. Words light up as they
 * are spoken; click any word to jump there. Words a task was found in are
 * underlined. Either recording can be muted.
 */
export default function MeetingPlayer({
  meetingId,
  segments,
  durationS,
  tasks = [],
  focus,
}: {
  meetingId: number;
  segments: Segment[];
  durationS: number;
  tasks?: TaskMark[];
  /** Play from just before where a task was said. */
  focus?: SourceFocus;
}) {
  const audios = useRef<Partial<Record<Track, HTMLAudioElement>>>({});
  const urls = useRef<string[]>([]);
  const [available, setAvailable] = useState<{ mic: boolean; system: boolean }>({ mic: false, system: false });
  const [tracksKnown, setTracksKnown] = useState(false);
  const [muted, setMuted] = useState<Record<Track, boolean>>({ mic: false, system: false });
  const [playing, setPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(durationS);
  const [loading, setLoading] = useState(false);
  const listRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    setTracksKnown(false);
    api.meetingTracks(meetingId).then((t) => {
      setAvailable(t);
      setTracksKnown(true);
    });
    return () => {
      Object.values(audios.current).forEach((a) => a?.pause());
      urls.current.forEach((u) => URL.revokeObjectURL(u));
      audios.current = {};
      urls.current = [];
    };
  }, [meetingId]);

  const tracks = (Object.keys(available) as Track[]).filter((t) => available[t]);
  const master = (): HTMLAudioElement | undefined => audios.current.system ?? audios.current.mic;

  // Follow the playhead and keep the two recordings in step.
  useEffect(() => {
    if (!playing) return;
    let raf = 0;
    const tick = () => {
      const m = master();
      if (m) {
        setTime(m.currentTime);
        for (const a of Object.values(audios.current)) {
          if (a && a !== m && !a.ended && Math.abs(a.currentTime - m.currentTime) > 0.15) a.currentTime = m.currentTime;
        }
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [playing]);

  const load = async () => {
    if (Object.keys(audios.current).length) return true;
    setLoading(true);
    try {
      for (const t of tracks) {
        const bytes = await api.meetingAudio(meetingId, t);
        const url = URL.createObjectURL(new Blob([bytes], { type: "audio/wav" }));
        urls.current.push(url);
        const a = new Audio(url);
        a.muted = muted[t];
        a.onloadedmetadata = () => isFinite(a.duration) && setDuration((d) => Math.max(d, a.duration));
        audios.current[t] = a;
      }
      const m = master();
      if (m) {
        m.onended = () => {
          // Finished: rewind so the next play starts from the beginning.
          Object.values(audios.current).forEach((a) => {
            if (a) {
              a.pause();
              a.currentTime = 0;
            }
          });
          setPlaying(false);
          setTime(0);
        };
      }
      return true;
    } catch {
      return false;
    } finally {
      setLoading(false);
    }
  };

  const play = async (from?: number) => {
    if (!(await load())) return;
    const all = Object.values(audios.current).filter(Boolean) as HTMLAudioElement[];
    if (from !== undefined) {
      all.forEach((a) => (a.currentTime = Math.min(from, isFinite(a.duration) ? a.duration : from)));
      setTime(from);
    }
    await Promise.all(all.map((a) => a.play().catch(() => {})));
    setPlaying(true);
  };

  const pause = () => {
    Object.values(audios.current).forEach((a) => a?.pause());
    setPlaying(false);
  };

  const toggleMute = (t: Track) => {
    setMuted((m) => {
      const next = { ...m, [t]: !m[t] };
      const a = audios.current[t];
      if (a) a.muted = next[t];
      return next;
    });
  };

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    play(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * duration);
  };

  // Words per line, and which task each word belongs to. A task's quote can
  // run across lines, so it's matched against the whole meeting at once.
  const lines = useMemo(() => {
    const words = segments.map((s) => (s.words && s.words.length > 0 ? s.words : spreadWords(s)));
    const flat = taskOfWords(words.flat().map((w) => w.w), tasks);
    let at = 0;
    return words.map((ws) => {
      const taskOf = flat.slice(at, at + ws.length);
      at += ws.length;
      return { words: ws, taskOf };
    });
  }, [segments, tasks]);

  const seekTo = useRef<(t: number) => void>(() => {});
  seekTo.current = (t: number) => {
    if (tracks.length) play(t);
  };
  const onSeek = useMemo(() => (t: number) => seekTo.current(t), []);

  // Opened from a task: start a little before its quote (once the transcript is in).
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus?.play || focused.current === focus.nonce || segments.length === 0 || !tracksKnown) return;
    focused.current = focus.nonce;
    const at = quoteStart(lines.flatMap((l) => l.words), focus.quote);
    if (at === null) toast("Couldn't find where this task was said — playing from the start");
    if (!tracks.length) {
      toast("The audio for this meeting is no longer available");
      return;
    }
    play(Math.max(0, (at ?? 0) - focus.leadS));
  }, [focus, lines, tracksKnown]);

  const activeIndex = segments.findIndex((s) => time >= s.start && time < s.end);
  useEffect(() => {
    if (!playing || activeIndex < 0) return;
    const el = listRef.current?.querySelector<HTMLElement>(`[data-seg="${activeIndex}"]`);
    el?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [activeIndex, playing]);

  const pct = duration ? Math.min(100, (time / duration) * 100) : 0;
  const started = playing || time > 0;

  return (
    <div>
      {tracks.length > 0 ? (
        <>
          <div className={`player ${playing ? "playing" : ""}`}>
            <button className="play-btn" onClick={() => (playing ? pause() : play())} disabled={loading} aria-label={playing ? "Pause" : "Play"}>
              {loading ? <span className="spinner" /> : playing ? <Pause size={15} /> : <Play size={15} />}
            </button>
            <div className="scrub" onClick={seek}>
              <div className="scrub-fill" style={{ width: `${pct}%` }} />
              <div className="scrub-knob" style={{ left: `${pct}%` }} />
            </div>
            <span className="time">
              {formatDuration(time)} / {formatDuration(duration)}
            </span>
          </div>
          <div className="row wrap" style={{ marginBottom: 12 }}>
            {tracks.map((t) => (
              <button key={t} className={`track-chip ${muted[t] ? "off" : ""}`} onClick={() => toggleMute(t)}>
                <span className={`track-dot ${t}`} />
                {TRACK_LABEL[t]}
                <span className="small faint">{muted[t] ? "muted" : ""}</span>
              </button>
            ))}
          </div>
        </>
      ) : (
        <p className="small muted" style={{ marginBottom: 12 }}>
          The audio for this meeting is no longer available.
        </p>
      )}

      {segments.length > 0 && (
        <div className="transcript" ref={listRef}>
          {segments.map((s, i) => {
            const state: LineState = !started ? "" : i === activeIndex ? "now" : time >= s.end ? "spoken" : "upcoming";
            return (
              <Line
                key={i}
                seg={s}
                index={i}
                words={lines[i].words}
                taskOf={lines[i].taskOf}
                state={state}
                time={state === "now" ? time : 0}
                onSeek={onSeek}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
