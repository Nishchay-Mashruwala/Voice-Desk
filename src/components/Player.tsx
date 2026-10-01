import { useEffect, useRef, useState } from "react";
import { api, formatDuration, type SourceFocus, type Word } from "../api";
import { quoteStart, taskOfWords, type TaskMark } from "../taskMarks";
import { toast } from "../toast";
import { Pause, Play } from "../icons";

// Only one recording plays at a time.
let playing: HTMLAudioElement | null = null;

const STATUS_HINT: Record<string, string> = {
  paused: "Heard while paused — not typed",
  captured: "Used for task recording — not typed",
  "not your voice": "Didn't match your voice — not typed",
  stopped: "Heard while stopping — not typed",
};

/**
 * Plays a listening session's recording with its transcript underneath.
 * Words light up as they are spoken; click any word to jump there.
 */
export default function Player({
  id,
  words,
  text,
  hasAudio,
  durationS,
  tasks = [],
  focus,
}: {
  id: number;
  words: Word[] | null;
  text: string;
  hasAudio: boolean;
  durationS: number;
  tasks?: TaskMark[];
  /** Play from just before where a task was said. */
  focus?: SourceFocus;
}) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const urlRef = useRef<string | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [time, setTime] = useState(0);
  const [duration, setDuration] = useState(durationS);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(
    () => () => {
      audioRef.current?.pause();
      if (urlRef.current) URL.revokeObjectURL(urlRef.current);
    },
    [],
  );

  // Smooth highlighting: follow the playhead every frame while playing.
  useEffect(() => {
    if (!isPlaying) return;
    let raf = 0;
    const tick = () => {
      if (audioRef.current) setTime(audioRef.current.currentTime);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [isPlaying]);

  const ensureAudio = async (): Promise<HTMLAudioElement | null> => {
    if (audioRef.current) return audioRef.current;
    setLoading(true);
    try {
      const bytes = await api.dictationAudio(id);
      const url = URL.createObjectURL(new Blob([bytes], { type: "audio/wav" }));
      urlRef.current = url;
      const a = new Audio(url);
      a.onloadedmetadata = () => isFinite(a.duration) && setDuration(a.duration);
      a.onplay = () => setIsPlaying(true);
      a.onpause = () => setIsPlaying(false);
      a.onended = () => {
        // Finished: rewind so the next play starts from the beginning.
        a.currentTime = 0;
        setIsPlaying(false);
        setTime(0);
      };
      audioRef.current = a;
      return a;
    } catch (e) {
      setError(String(e));
      return null;
    } finally {
      setLoading(false);
    }
  };

  const play = async (from?: number) => {
    const a = await ensureAudio();
    if (!a) return;
    if (playing && playing !== a) playing.pause();
    playing = a;
    if (from !== undefined) {
      a.currentTime = from;
      setTime(from);
    }
    await a.play();
  };

  // Opened from a task: start a little before its quote.
  const focused = useRef<number | null>(null);
  useEffect(() => {
    if (!focus?.play || focused.current === focus.nonce) return;
    focused.current = focus.nonce;
    if (!hasAudio) {
      toast("The audio for this recording is no longer available");
      return;
    }
    const at = words && words.length > 0 ? quoteStart(words, focus.quote) : null;
    if (at === null) toast("Couldn't find where this task was said — playing from the start");
    play(Math.max(0, (at ?? 0) - focus.leadS));
  }, [focus]);

  const toggle = () => (isPlaying ? audioRef.current?.pause() : play());

  const seek = (e: React.MouseEvent<HTMLDivElement>) => {
    const r = e.currentTarget.getBoundingClientRect();
    play(Math.max(0, Math.min(1, (e.clientX - r.left) / r.width)) * duration);
  };

  const pct = duration ? Math.min(100, (time / duration) * 100) : 0;
  const started = isPlaying || time > 0;
  const plain = text.split(/\s+/).filter(Boolean);
  const taskOf = taskOfWords(words && words.length > 0 ? words.map((w) => w.w) : plain, tasks);
  const taskTitle = (i: number) => (taskOf[i] ? `Task: ${taskOf[i]}` : undefined);

  return (
    <div>
      {hasAudio && (
        <div className={`player ${isPlaying ? "playing" : ""}`}>
          <button className="play-btn" onClick={toggle} disabled={loading} aria-label={isPlaying ? "Pause" : "Play"}>
            {loading ? <span className="spinner" /> : isPlaying ? <Pause size={15} /> : <Play size={15} />}
          </button>
          <div className="scrub" onClick={seek}>
            <div className="scrub-fill" style={{ width: `${pct}%` }} />
            <div className="scrub-knob" style={{ left: `${pct}%` }} />
          </div>
          <span className="time">
            {formatDuration(time)} / {formatDuration(duration)}
          </span>
        </div>
      )}
      {error && <div className="small bad">{error}</div>}
      {words && words.length > 0 ? (
        <p className={`karaoke ${started ? "" : "idle"}`}>
          {words.map((w, i) => {
            const state = time >= w.e ? "spoken" : time >= w.s ? "now" : "";
            const notTyped = w.st && w.st !== "typed" ? "not-typed" : "";
            return (
              <span key={i}>
                <span
                  className={`w ${started ? state : ""} ${notTyped} ${taskOf[i] ? "task-word" : ""}`}
                  title={taskTitle(i) ?? (w.st ? STATUS_HINT[w.st] : undefined)}
                  onClick={() => hasAudio && play(w.s)}
                >
                  {w.w}
                </span>{" "}
              </span>
            );
          })}
        </p>
      ) : tasks.length > 0 ? (
        <p className="karaoke idle">
          {plain.map((w, i) => (
            <span key={i}>
              <span className={taskOf[i] ? "w task-word" : undefined} title={taskTitle(i)}>
                {w}
              </span>{" "}
            </span>
          ))}
        </p>
      ) : (
        <p className="karaoke idle">{text}</p>
      )}
    </div>
  );
}
