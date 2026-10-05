import { memo, useEffect, useMemo, useRef, useState } from "react";
import { api, audioBlob, formatDuration, type Segment, type SourceFocus, type Word } from "../api";
import { Pencil, Pause, Play } from "../icons";
import { retimeWords } from "../retime";
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

type LineAction =
  | { kind: "edit"; index: number }
  | { kind: "save"; index: number; text: string }
  | { kind: "cancel" }
  | { kind: "rename"; speaker: string };

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
  editing,
  onSeek,
  onAction,
}: {
  seg: Segment;
  index: number;
  words: Word[];
  taskOf: (string | null)[];
  state: LineState;
  time: number;
  editing: boolean;
  onSeek: (t: number) => void;
  onAction: (a: LineAction) => void;
}) {
  const [draft, setDraft] = useState(seg.text);
  useEffect(() => setDraft(seg.text), [seg.text, editing]);
  if (editing) {
    const save = () => onAction({ kind: "save", index, text: draft });
    return (
      <div data-seg={index} className={`seg editing ${seg.speaker === "Me" ? "me" : ""}`}>
        <span className="seg-time">{formatDuration(seg.start)}</span>
        <span className="seg-speaker">{seg.speaker}</span>
        <div className="seg-edit">
          <textarea
            autoFocus
            value={draft}
            rows={Math.min(6, Math.ceil(draft.length / 70) + 1)}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                save();
              }
              if (e.key === "Escape") onAction({ kind: "cancel" });
            }}
          />
          <div className="row">
            <button className="primary" onClick={save} disabled={!draft.trim()}>
              Save
            </button>
            <button onClick={() => onAction({ kind: "cancel" })}>Cancel</button>
          </div>
        </div>
      </div>
    );
  }
  return (
    <div data-seg={index} className={`seg ${seg.speaker === "Me" ? "me" : ""} ${state}`} onClick={() => onSeek(seg.start)}>
      <span className="seg-time">{formatDuration(seg.start)}</span>
      {seg.speaker === "Me" ? (
        <span className="seg-speaker">{seg.speaker}</span>
      ) : (
        <button
          className="seg-speaker seg-speaker-btn"
          title="Rename this speaker"
          onClick={(e) => {
            e.stopPropagation();
            onAction({ kind: "rename", speaker: seg.speaker });
          }}
        >
          {seg.speaker}
        </button>
      )}
      <button
        className="ghost icon seg-edit-btn"
        title="Fix the words in this line"
        onClick={(e) => {
          e.stopPropagation();
          onAction({ kind: "edit", index });
        }}
      >
        <Pencil size={13} />
      </button>
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
  onEdited,
  onFindTasks,
}: {
  meetingId: number;
  segments: Segment[];
  durationS: number;
  tasks?: TaskMark[];
  /** A line or speaker name changed (reload the transcript). */
  onEdited?: () => void;
  /** Offered after renaming, so tasks use the new name. */
  onFindTasks?: () => void;
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

  // Bumped when the meeting changes or the player closes: audio still loading
  // for the old one is then dropped instead of created and played.
  const gen = useRef(0);
  useEffect(() => {
    const mine = ++gen.current;
    setTracksKnown(false);
    api.meetingTracks(meetingId).then((t) => {
      if (gen.current !== mine) return;
      setAvailable(t);
      setTracksKnown(true);
    });
    return () => {
      gen.current++;
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
    const mine = gen.current;
    setLoading(true);
    try {
      for (const t of tracks) {
        const bytes = await api.meetingAudio(meetingId, t);
        if (gen.current !== mine) return false;
        const url = URL.createObjectURL(audioBlob(bytes));
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
      if (gen.current === mine) setLoading(false);
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

  // Fixing a line's words, and renaming a speaker.
  const [editing, setEditing] = useState<number | null>(null);
  const [renaming, setRenaming] = useState<string | null>(null);
  const [newName, setNewName] = useState("");
  const [remember, setRemember] = useState(true);
  const [savingName, setSavingName] = useState(false);
  const act = useRef<(a: LineAction) => void>(() => {});
  act.current = async (a: LineAction) => {
    if (a.kind === "edit") setEditing(a.index);
    if (a.kind === "cancel") setEditing(null);
    if (a.kind === "rename") {
      setRenaming(a.speaker);
      setNewName(/^Speaker \d+$|^Others$/.test(a.speaker) ? "" : a.speaker);
    }
    if (a.kind === "save") {
      const seg = segments[a.index];
      const text = a.text.trim();
      if (!seg || !text) return;
      try {
        await api.updateTranscriptLine(meetingId, a.index, text, retimeWords(lines[a.index].words, text, seg.start, seg.end));
        setEditing(null);
        onEdited?.();
      } catch (e) {
        toast(`Couldn't save: ${e}`);
      }
    }
  };
  const onAction = useMemo(() => (a: LineAction) => act.current(a), []);
  const saveName = async () => {
    if (!renaming || !newName.trim()) return;
    setSavingName(true);
    try {
      await api.renameSpeaker(meetingId, renaming, newName.trim(), remember);
      toast(
        remember ? `Renamed — ${newName.trim()}'s voice will be recognised in future meetings` : `Renamed to ${newName.trim()}`,
        onFindTasks ? { action: { label: "Find tasks again", run: onFindTasks } } : {},
      );
      setRenaming(null);
      onEdited?.();
    } catch (e) {
      toast(String(e));
    } finally {
      setSavingName(false);
    }
  };

  // Opened from a task: start a little before its quote (once the transcript is in).
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus?.play || focused.current === focus.nonce || segments.length === 0 || !tracksKnown) return;
    focused.current = focus.nonce;
    const at = focus.atS ?? quoteStart(lines.flatMap((l) => l.words), focus.quote);
    if (at === null && focus.quote) toast("Couldn't find where this task was said — playing from the start");
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

      {renaming && (
        <div className="rename-speaker">
          <span className="small">
            Rename <b>{renaming}</b> to
          </span>
          <input
            autoFocus
            value={newName}
            placeholder="Their name"
            onChange={(e) => setNewName(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter") saveName();
              if (e.key === "Escape") setRenaming(null);
            }}
          />
          <label className="small row" title="Their voice is saved on this computer only">
            <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
            Recognise this voice in future meetings
          </label>
          <button className="primary" onClick={saveName} disabled={!newName.trim() || savingName}>
            {savingName ? <span className="spinner" /> : "Rename"}
          </button>
          <button onClick={() => setRenaming(null)}>Cancel</button>
        </div>
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
                editing={editing === i}
                onSeek={onSeek}
                onAction={onAction}
              />
            );
          })}
        </div>
      )}
    </div>
  );
}
