import { useEffect, useState } from "react";
import {
  api,
  firstPhrase,
  formatDate,
  formatDuration,
  useEvent,
  type Dictation,
  type HeardPart,
  type SessionStatus,
  type Settings,
  type SourceFocus,
} from "../api";
import Player from "../components/Player";
import { Copy, ListCheck, Mic, Pause, Play, Stop, Trash, Users } from "../icons";
import { confirmDialog } from "../confirm";
import { toast, undoToast } from "../toast";

const STATE_TITLE: Record<string, string> = {
  idle: "Ready when you are",
  starting: "Warming up…",
  listening: "Listening",
  paused: "Paused",
  stopping: "Finishing up…",
};

const STATUS_BADGE: Record<string, { label: string; cls: string }> = {
  typed: { label: "Typed", cls: "ok" },
  captured: { label: "Task input", cls: "rec" },
  paused: { label: "Paused", cls: "warn" },
  "not your voice": { label: "Not you", cls: "" },
  stopped: { label: "Skipped", cls: "" },
  done: { label: "Command", cls: "accent" },
  ignored: { label: "Ignored", cls: "" },
};

const COMMAND_LABEL: Record<string, string> = {
  stop: "Stop listening",
  pause: "Pause typing",
  resume: "Resume typing",
  record_tasks: "Start recording tasks",
  tasks_recorded: "Finish recording tasks",
};

interface FeedEntry {
  id: number;
  parts: HeardPart[];
}

let feedId = 0;

export default function ListenView({
  settings,
  session,
  focus,
  onOpenMeeting,
}: {
  settings: Settings | null;
  session: SessionStatus | null;
  /** Opened from a task: the recording it came from. */
  focus?: SourceFocus;
  onOpenMeeting: (id: number) => void;
}) {
  const [items, setItems] = useState<Dictation[]>([]);
  const [feed, setFeed] = useState<FeedEntry[]>([]);
  const [level, setLevel] = useState(0);

  useEffect(() => {
    api.listDictations().then(setItems);
  }, []);
  useEvent<Dictation>("dictation-added", (d) => setItems((prev) => [d, ...prev]));
  // Tasks edited or deleted elsewhere change what's underlined.
  useEvent("tasks-changed", () => api.listDictations().then(setItems));
  useEvent<{ parts: HeardPart[] }>("heard", (h) =>
    setFeed((prev) => [...prev.slice(-5), { id: feedId++, parts: h.parts }]),
  );

  const state = session?.state ?? "idle";
  const active = state !== "idle";
  useEffect(() => {
    if (!active) return;
    const t = setInterval(async () => setLevel((await api.audioLevels()).listening ?? 0), 80);
    return () => clearInterval(t);
  }, [active]);

  // Opened from a task: scroll to its recording and flash it.
  const focusedId = focus?.dictationId;
  useEffect(() => {
    if (focusedId === undefined) return;
    document.querySelector(`[data-dictation="${focusedId}"]`)?.scrollIntoView({ block: "center", behavior: "smooth" });
  }, [focusedId, focus?.nonce]);

  const toggle = async () => {
    try {
      await api.sessionToggle();
    } catch (e) {
      toast(String(e));
    }
  };

  const remove = async (d: Dictation) => {
    const ok = await confirmDialog({
      title: "Delete this recording?",
      message: `The recording from ${formatDate(d.created_at)} and its text will be deleted.`,
    });
    if (!ok) return;
    setItems((prev) => prev.filter((x) => x.id !== d.id));
    undoToast(
      "Recording deleted",
      () => setItems((prev) => [d, ...prev].sort((a, b) => b.id - a.id)),
      () => api.deleteDictation(d.id),
    );
  };

  const [finding, setFinding] = useState<number | null>(null);
  const findTasks = async (d: Dictation) => {
    if (d.tasks.length > 0) {
      toast("Tasks from this recording are already in My tasks");
      return;
    }
    setFinding(d.id);
    try {
      const n = await api.dictationFindTasks(d.id);
      toast(n === 0 ? "No tasks found in this recording" : `${n} task${n === 1 ? "" : "s"} added to My tasks`);
    } catch (e) {
      toast(`Couldn't find tasks: ${e}`);
    } finally {
      setFinding(null);
    }
  };

  const [converting, setConverting] = useState<number | null>(null);
  const makeMeeting = async (d: Dictation) => {
    const ok = await confirmDialog({
      title: "Make it a meeting?",
      message:
        "It's transcribed again with speaker detection (about as long as the recording), then tasks are found. " +
        "It moves to the Meetings page.",
      confirmLabel: "Make meeting",
    });
    if (!ok) return;
    setConverting(d.id);
    try {
      const id = await api.dictationToMeeting(d.id);
      setItems((prev) => prev.filter((x) => x.id !== d.id));
      toast("Moved to Meetings — transcribing", { action: { label: "View", run: () => onOpenMeeting(id) } });
    } catch (e) {
      toast(`Couldn't make it a meeting: ${e}`);
    } finally {
      setConverting(null);
    }
  };

  const copy = async (d: Dictation) => {
    await navigator.clipboard.writeText(d.text);
    toast("Copied to clipboard");
  };

  const name = settings?.assistant_name || "Jarvis";
  const hotkey = settings?.dictation_hotkey ?? "Ctrl+Shift+Space";
  const mode = settings?.dictation_mode ?? "toggle";
  const how =
    mode === "hold"
      ? "hold"
      : mode === "double"
        ? "double-press"
        : mode === "long"
          ? `hold for ${settings?.long_press_s ?? 5}s`
          : "press";
  const orbCls = session?.capturing ? "capturing listening" : state === "listening" ? "listening" : state;
  const scale = 1 + Math.min(0.35, Math.sqrt(level) * 2.2);

  const commands = settings
    ? [
        ["pause", settings.cmd_pause],
        ["resume", settings.cmd_resume],
        ["record_tasks", settings.cmd_record_tasks],
        ["tasks_recorded", settings.cmd_tasks_recorded],
        ["stop", settings.cmd_stop],
      ]
    : [];

  return (
    <section className="page">
      <header className="page-header">
        <h1>
          Speak, and it <span className="gradient-text">writes</span>.
        </h1>
        <p>
          Put your cursor anywhere and {how} <kbd>{hotkey}</kbd>. Each phrase is typed as soon as you pause — no need
          to stop first.
        </p>
      </header>

      <div className={`card hero ${active ? "active" : ""}`}>
        <button className={`orb ${orbCls}`} onClick={toggle} aria-label={active ? "Stop listening" : "Start listening"}>
          {active && <span className="orb-level" style={{ transform: `scale(${scale})` }} />}
          {active ? <Stop size={34} /> : <Mic size={40} />}
        </button>
        <div>
          <div className="hero-state">
            {session?.capturing && state === "listening" ? (
              <span style={{ color: "#ff4d6d" }}>Recording tasks</span>
            ) : (
              STATE_TITLE[state]
            )}
          </div>
          <p className="muted">
            {!active && (
              <>
                Click the microphone or {how} <kbd>{hotkey}</kbd>.
              </>
            )}
            {state === "starting" && "Loading the speech model — speak anyway, nothing is lost."}
            {state === "listening" && !session?.capturing && "Text appears at your cursor after each short pause."}
            {state === "paused" && `Not typing. Say “${name}, ${firstPhrase(settings?.cmd_resume ?? "resume")}” to continue.`}
            {session?.capturing &&
              `Everything said now becomes tasks. Say “${name}, ${firstPhrase(settings?.cmd_tasks_recorded ?? "tasks recorded")}” when done.`}
          </p>
          {active && (
            <div className="hero-controls">
              <button disabled={!!session?.capturing} onClick={() => api.sessionSetWriting(state === "paused")}>
                {state === "paused" ? <Play size={15} /> : <Pause size={15} />}
                {state === "paused" ? "Resume" : "Pause"}
              </button>
              <button className={session?.capturing ? "rec" : ""} onClick={() => api.captureToggle()}>
                <ListCheck size={16} />
                {session?.capturing ? "Finish tasks" : "Record tasks"}
              </button>
              <button onClick={() => api.sessionStop()}>
                <Stop size={13} /> Stop
              </button>
            </div>
          )}
          {session && session.processing > 0 && (
            <div className="row small muted" style={{ marginTop: 10 }}>
              <span className="spinner dark" /> Turning your recording into tasks…
            </div>
          )}
        </div>
      </div>

      <div className="compact-row">
        <div className="card compact live-card">
          <div className="compact-head">
            <span className="compact-title">Live</span>
            {active && <span className="dot live" />}
          </div>
          {feed.length === 0 ? (
            <span className="small muted">What you say appears here.</span>
          ) : (
            <div className="feed">
              {feed.slice(-3).map((f) =>
                f.parts.map((p, i) => {
                  const badge = STATUS_BADGE[p.status] ?? { label: p.status, cls: "" };
                  return (
                    <div key={`${f.id}-${i}`} className={`feed-item ${p.status === "typed" ? "" : "dim"}`}>
                      <span className="feed-text">
                        {p.type === "command" ? `“${name}” → ${COMMAND_LABEL[p.command ?? ""] ?? p.command}` : p.text}
                      </span>
                      <span className={`badge ${badge.cls}`}>{badge.label}</span>
                    </div>
                  );
                }),
              )}
            </div>
          )}
          <input className="scratch" placeholder="Try it here: click, then use your shortcut and talk…" />
        </div>

        <div className="card compact">
          <div className="compact-head">
            <span className="compact-title">Voice commands</span>
          </div>
          <div className="command-chips">
            {commands.map(([id, phrases]) => (
              <span key={id} className="command-chip" title={COMMAND_LABEL[id]}>
                <span className="name">{name},</span> {firstPhrase(phrases)}
              </span>
            ))}
          </div>
        </div>
      </div>

      <h3>History</h3>
      {items.length === 0 ? (
        <div className="empty">Your recordings will appear here, with the text highlighted as it plays.</div>
      ) : (
        <ul className="list stagger">
          {items.map((d, i) => (
            <li
              key={d.id}
              data-dictation={d.id}
              className={`card history-item ${focusedId === d.id ? "flash" : ""}`}
              style={{ "--i": i } as React.CSSProperties}
            >
              <div className="history-head">
                <span className="small muted grow">
                  {formatDate(d.created_at)} · {formatDuration(d.duration_ms / 1000)}
                </span>
                <button className="ghost" onClick={() => findTasks(d)} disabled={finding !== null}>
                  {finding === d.id ? <span className="spinner dark" /> : <ListCheck size={15} />}{" "}
                  {d.tasks.length > 0 ? `${d.tasks.length} task${d.tasks.length === 1 ? "" : "s"} found` : "Find tasks"}
                </button>
                <button
                  className="ghost icon"
                  title={d.has_audio ? "Make it a meeting" : "Audio deleted — can't make it a meeting"}
                  onClick={() => makeMeeting(d)}
                  disabled={!d.has_audio || converting !== null || finding !== null}
                >
                  {converting === d.id ? <span className="spinner dark" /> : <Users size={16} />}
                </button>
                <button className="ghost icon" title="Copy text" onClick={() => copy(d)}>
                  <Copy size={16} />
                </button>
                <button className="ghost icon danger" title="Delete" onClick={() => remove(d)}>
                  <Trash size={16} />
                </button>
              </div>
              <Player
                id={d.id}
                words={d.words}
                text={d.text}
                hasAudio={d.has_audio}
                durationS={d.duration_ms / 1000}
                tasks={d.tasks}
                focus={focusedId === d.id ? focus : undefined}
              />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
