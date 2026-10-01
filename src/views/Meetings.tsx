import { useCallback, useEffect, useState } from "react";
import {
  api,
  formatClock,
  formatDate,
  formatDuration,
  useEvent,
  type Levels,
  type Meeting,
  type MeetingProgress,
  type Segment,
  type SourceFocus,
  type Task,
} from "../api";
import { Mic, Refresh, Sparkle, Stop, Trash } from "../icons";
import { confirmDialog } from "../confirm";
import { toast, undoToast } from "../toast";
import MeetingPlayer from "../components/MeetingPlayer";
import { TaskList } from "./Tasks";

function LevelMeter({ label, value }: { label: string; value: number | null }) {
  const pct = value == null ? 0 : Math.min(100, Math.sqrt(value) * 250);
  return (
    <div className="meter">
      <span className="small muted">
        {label}
        {value == null && " · off"}
      </span>
      <div className="progress-track">
        <div className="progress-fill" style={{ width: `${pct}%`, transition: "width 0.12s linear" }} />
      </div>
    </div>
  );
}

function Recorder({ onChange }: { onChange: () => void }) {
  const [activeId, setActiveId] = useState<number | null>(null);
  const [title, setTitle] = useState("");
  const [startedAt, setStartedAt] = useState(0);
  const [elapsed, setElapsed] = useState(0);
  const [levels, setLevels] = useState<Levels>({ listening: null, mic: null, system: null, enroll: null });
  const [busy, setBusy] = useState(false);

  // Recordings also start and stop from the overlay (call offer, Stop).
  const sync = useCallback(
    () =>
      api.activeMeeting().then((m) => {
        setActiveId(m?.id ?? null);
        if (m) setStartedAt(Date.now() - m.elapsed_s * 1000);
      }),
    [],
  );
  useEffect(() => {
    sync();
  }, [sync]);
  useEvent("meetings-changed", sync);

  useEffect(() => {
    if (!activeId) return;
    const t = setInterval(async () => {
      setElapsed((Date.now() - startedAt) / 1000);
      setLevels(await api.audioLevels());
    }, 150);
    return () => clearInterval(t);
  }, [activeId, startedAt]);

  const start = async () => {
    setBusy(true);
    try {
      const r = await api.startMeeting(title);
      setActiveId(r.id);
      setStartedAt(Date.now());
      setElapsed(0);
      setTitle("");
      if (r.warning) toast(r.warning);
      onChange();
    } catch (e) {
      toast(String(e));
    } finally {
      setBusy(false);
    }
  };

  const stop = async () => {
    setBusy(true);
    try {
      await api.stopMeeting();
      setActiveId(null);
      setTitle("");
      toast("Processing in the background — your tasks will appear when it's done.");
      onChange();
    } catch (e) {
      toast(String(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className={`card recorder ${activeId ? "live" : ""}`}>
      {activeId ? (
        <>
          <span className="dot live" style={{ width: 12, height: 12 }} />
          <div className="grow">
            <div className="rec-time">{formatClock(elapsed)}</div>
            <LevelMeter label="You (microphone)" value={levels.mic} />
            <LevelMeter label="Others (speakers)" value={levels.system} />
          </div>
          <button className="rec" onClick={stop} disabled={busy}>
            <Stop size={13} /> Stop &amp; find tasks
          </button>
        </>
      ) : (
        <>
          <input
            className="grow"
            placeholder="Meeting title (optional)"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && start()}
          />
          <button className="rec" onClick={start} disabled={busy}>
            ● Start recording
          </button>
        </>
      )}
    </div>
  );
}

const STATUS_LABEL: Record<Meeting["status"], string> = {
  recording: "Recording",
  transcribing: "Transcribing",
  extracting: "Finding tasks",
  done: "Done",
  error: "Error",
};

function MeetingDetail({
  meeting,
  progress,
  onChange,
  onRemove,
  onMoved,
  focus,
}: {
  meeting: Meeting;
  progress?: MeetingProgress;
  onChange: () => void;
  onRemove: () => void;
  /** Turned into a Listen recording (its new id). */
  onMoved: (dictationId: number) => void;
  focus?: SourceFocus;
}) {
  const [segments, setSegments] = useState<Segment[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [title, setTitle] = useState(meeting.title);

  useEffect(() => setTitle(meeting.title), [meeting.id, meeting.title]);
  useEffect(() => {
    if (["done", "extracting", "error"].includes(meeting.status)) api.getTranscript(meeting.id).then(setSegments);
    else setSegments([]);
  }, [meeting.id, meeting.status]);

  // Underlined in the transcript; edits and deletes elsewhere update them.
  const loadTasks = useCallback(() => api.listTasks(meeting.id).then(setTasks), [meeting.id]);
  useEffect(() => {
    loadTasks();
  }, [loadTasks, meeting.task_count]);
  useEvent("tasks-changed", loadTasks);

  const processing = meeting.status === "transcribing" || meeting.status === "extracting";

  const rename = async () => {
    if (title.trim() && title !== meeting.title) {
      await api.renameMeeting(meeting.id, title.trim());
      onChange();
    }
  };
  const [moving, setMoving] = useState(false);
  const moveToListen = async () => {
    const ok = await confirmDialog({
      title: "Move to Listen history?",
      message:
        "It becomes a normal recording: both tracks are mixed into one, and its tasks are kept. " +
        "Like other recordings, its audio is deleted after your “keep audio” days. You can make it a meeting again later.",
      confirmLabel: "Move",
    });
    if (!ok) return;
    setMoving(true);
    try {
      const d = await api.meetingToDictation(meeting.id);
      onMoved(d.id);
    } catch (e) {
      toast(`Couldn't move it: ${e}`);
    } finally {
      setMoving(false);
    }
  };

  const reprocess = async (transcribe: boolean) => {
    try {
      await api.reprocessMeeting(meeting.id, transcribe);
      onChange();
    } catch (e) {
      toast(String(e));
    }
  };

  return (
    <div className="card meeting-detail" key={meeting.id} style={{ animation: "page-in 0.35s var(--ease) both" }}>
      <input className="title-input" value={title} onChange={(e) => setTitle(e.target.value)} onBlur={rename} />
      <div className="row wrap small muted" style={{ marginTop: 4 }}>
        <span>{formatDate(meeting.started_at)}</span>
        {meeting.duration_s != null && <span>· {formatDuration(meeting.duration_s)}</span>}
        <span className={`badge ${meeting.status === "done" ? "ok" : meeting.status === "error" ? "rec" : "accent"}`}>
          {STATUS_LABEL[meeting.status]}
        </span>
      </div>

      {processing && (
        <div style={{ margin: "18px 0" }}>
          <div className="row small" style={{ marginBottom: 8 }}>
            <span className="spinner dark" /> {progress?.stage ?? STATUS_LABEL[meeting.status]}…
          </div>
          <div className="progress-track">
            <div className={`progress-fill ${progress ? "" : "indeterminate"}`} style={{ width: `${progress?.pct ?? 5}%` }} />
          </div>
        </div>
      )}

      {meeting.status === "error" && <div className="error-box">{meeting.error}</div>}

      {meeting.summary && (
        <>
          <h3>
            <Sparkle size={12} /> Summary
          </h3>
          <p>{meeting.summary}</p>
        </>
      )}

      {(meeting.status === "done" || meeting.task_count > 0) && (
        <>
          <h3>Your tasks</h3>
          <TaskList meetingId={meeting.id} />
        </>
      )}

      {meeting.status !== "recording" && !processing && (
        <>
          <h3>Recording &amp; transcript</h3>
          <MeetingPlayer meetingId={meeting.id} segments={segments} durationS={meeting.duration_s ?? 0} tasks={tasks} focus={focus} />
        </>
      )}

      {!processing && meeting.status !== "recording" && (
        <div className="row wrap meeting-actions" style={{ marginTop: 22, paddingTop: 16, borderTop: "1px solid var(--border)" }}>
          <button className="primary" onClick={() => reprocess(false)} disabled={segments.length === 0}>
            <Sparkle size={15} /> Find tasks
          </button>
          {meeting.kind === "meeting" && (
            <button onClick={() => reprocess(true)}>
              <Refresh size={15} /> Re-transcribe
            </button>
          )}
          <span className="grow" />
          <button className="ghost" onClick={moveToListen} disabled={moving}>
            {moving ? <span className="spinner dark" /> : <Mic size={15} />} Move to Listen history
          </button>
          <button className="ghost danger" onClick={onRemove}>
            <Trash size={15} /> Delete
          </button>
        </div>
      )}
    </div>
  );
}

export default function MeetingsView({
  focus,
  onOpenDictation,
}: {
  focus?: SourceFocus;
  onOpenDictation: (id: number) => void;
}) {
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [selected, setSelected] = useState<number | null>(null);
  const [progress, setProgress] = useState<Record<number, MeetingProgress>>({});
  // Deleted but still undoable: hidden until the undo time runs out.
  const [hidden, setHidden] = useState<Set<number>>(new Set());

  // Only real meetings here: voice task recordings and "Find tasks" runs
  // belong to their recording on the Listen page.
  const load = useCallback(() => api.listMeetings().then((all) => setMeetings(all.filter((m) => m.kind === "meeting"))), []);
  // Opened from a task or a conversion: show that meeting.
  useEffect(() => {
    if (focus?.meetingId != null) setSelected(focus.meetingId);
  }, [focus]);
  useEffect(() => {
    load();
  }, [load]);

  useEvent("meetings-changed", load);
  useEvent<MeetingProgress>("meeting-progress", (p) => setProgress((prev) => ({ ...prev, [p.id]: p })));
  useEvent<{ id: number; message: string }>("meeting-warning", (w) => toast(w.message));

  const visible = meetings.filter((m) => !hidden.has(m.id));
  const current = visible.find((m) => m.id === selected) ?? visible[0];

  const remove = async (m: Meeting) => {
    const ok = await confirmDialog({
      title: "Delete this meeting?",
      message: `“${m.title}” will be deleted with its transcript, audio, and ${m.task_count} task${m.task_count === 1 ? "" : "s"}.`,
    });
    if (!ok) return;
    const unhide = () =>
      setHidden((h) => {
        const n = new Set(h);
        n.delete(m.id);
        return n;
      });
    setHidden((h) => new Set(h).add(m.id));
    undoToast("Meeting deleted", unhide, async () => {
      try {
        await api.deleteMeeting(m.id);
        await load();
      } catch (e) {
        toast(`Couldn't delete the meeting: ${e}`);
      }
      unhide();
    });
  };

  return (
    <section className="page">
      <header className="page-header">
        <h1>Meetings</h1>
        <p>
          Records your microphone (you) and your speakers (everyone else), then finds the tasks assigned to you.
          Headphones keep the two apart best.
        </p>
      </header>
      <Recorder onChange={load} />
      {visible.length === 0 ? (
        <div className="empty" style={{ marginTop: 16 }}>
          No meetings yet.
        </div>
      ) : (
        <div className="split">
          <ul className="meeting-list stagger">
            {visible.map((m, i) => (
              <li
                key={m.id}
                className={`meeting-item ${current?.id === m.id ? "active" : ""}`}
                style={{ "--i": i } as React.CSSProperties}
                onClick={() => setSelected(m.id)}
              >
                <div className="meeting-title">{m.title}</div>
                <div className="small muted">
                  {formatDate(m.started_at)} ·{" "}
                  {m.status === "done" ? `${m.task_count} task${m.task_count === 1 ? "" : "s"}` : STATUS_LABEL[m.status]}
                </div>
              </li>
            ))}
          </ul>
          {current && (
            <MeetingDetail
              key={current.id}
              meeting={current}
              progress={progress[current.id]}
              onChange={load}
              onRemove={() => remove(current)}
              onMoved={(id) => {
                setSelected(null);
                load();
                toast("Moved to Listen history", { action: { label: "View", run: () => onOpenDictation(id) } });
              }}
              focus={focus?.meetingId === current.id ? focus : undefined}
            />
          )}
        </div>
      )}
    </section>
  );
}
