import { useCallback, useEffect, useRef, useState } from "react";
import { api, formatDate, useEvent, type Task } from "../api";
import { confirmDialog } from "../confirm";
import { Check, Clock, Copy, Grip, Pencil, Play, Trash } from "../icons";
import { toast, undoToast } from "../toast";

function TaskRow({
  task,
  index,
  showMeeting,
  dragging,
  dropTarget,
  onToggle,
  onSave,
  onDelete,
  onOpenSource,
  dragHandlers,
}: {
  task: Task;
  index: number;
  showMeeting: boolean;
  dragging: boolean;
  dropTarget: boolean;
  onToggle: () => void;
  onSave: (description: string, due: string | null) => void;
  onDelete: () => void;
  onOpenSource?: () => void;
  dragHandlers: React.HTMLAttributes<HTMLLIElement> & { draggable: boolean };
}) {
  const [editing, setEditing] = useState(false);
  const [desc, setDesc] = useState(task.description);
  const [due, setDue] = useState(task.due ?? "");

  const save = () => {
    if (desc.trim()) onSave(desc.trim(), due.trim() || null);
    setEditing(false);
  };
  const cancel = () => {
    setDesc(task.description);
    setDue(task.due ?? "");
    setEditing(false);
  };
  const copy = async () => {
    await navigator.clipboard.writeText(task.description);
    toast("Task copied");
  };
  const keys = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") save();
    if (e.key === "Escape") cancel();
  };

  return (
    <li
      className={`task ${task.done ? "done" : ""} ${dragging ? "dragging" : ""} ${dropTarget ? "drop-target" : ""}`}
      style={{ "--i": index } as React.CSSProperties}
      {...(editing ? {} : dragHandlers)}
    >
      {!task.done && (
        <span className="grip" title="Drag to reorder">
          <Grip size={16} />
        </span>
      )}
      <button className={`checkbox ${task.done ? "on" : ""}`} onClick={onToggle} aria-label="Done">
        <Check size={13} strokeWidth={3} />
      </button>
      <div className="grow">
        {editing ? (
          <div className="task-edit">
            <input autoFocus value={desc} onChange={(e) => setDesc(e.target.value)} onKeyDown={keys} />
            <input value={due} placeholder="Due (e.g. Friday)" onChange={(e) => setDue(e.target.value)} onKeyDown={keys} />
            <div className="row" style={{ gridColumn: "1 / -1" }}>
              <button className="primary" onClick={save}>
                Save
              </button>
              <button onClick={cancel}>Cancel</button>
            </div>
          </div>
        ) : (
          <>
            <div className="task-text" onDoubleClick={() => setEditing(true)}>
              {task.description}
            </div>
            <div className="task-meta">
              {task.due && (
                <span className="badge accent">
                  <Clock size={12} /> {task.due}
                </span>
              )}
              {task.assigned_by && (
                <span className="badge">{task.assigned_by === "Self" ? "Your note" : `From ${task.assigned_by}`}</span>
              )}
              {showMeeting && task.meeting_title && (
                <button
                  className="badge badge-link"
                  title="Open where this was said"
                  disabled={!onOpenSource}
                  onClick={onOpenSource}
                >
                  <Play size={10} /> {task.meeting_title}
                </button>
              )}
              <span className="small faint">{formatDate(task.created_at)}</span>
            </div>
            {task.quote && <blockquote className="quote">“{task.quote}”</blockquote>}
          </>
        )}
      </div>
      {!editing && (
        <div className="task-actions">
          <button className="ghost icon" title="Copy task" onClick={copy}>
            <Copy size={15} />
          </button>
          <button className="ghost icon" title="Edit" onClick={() => setEditing(true)}>
            <Pencil size={15} />
          </button>
          <button className="ghost icon danger" title="Delete" onClick={onDelete}>
            <Trash size={15} />
          </button>
        </div>
      )}
    </li>
  );
}

/** Task list, optionally scoped to one meeting. Drag to reorder; edits save instantly. */
export function TaskList({
  meetingId = null,
  showMeeting = false,
  onOpenSource,
}: {
  meetingId?: number | null;
  showMeeting?: boolean;
  /** Open the recording a task came from, at the point it was said. */
  onOpenSource?: (t: Task) => void;
}) {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [hidden, setHidden] = useState<Set<number>>(new Set());
  const [draft, setDraft] = useState("");
  const [showDone, setShowDone] = useState(false);
  const [dragId, setDragId] = useState<number | null>(null);
  const [overId, setOverId] = useState<number | null>(null);
  const orderBeforeDrag = useRef<Task[]>([]);

  const load = useCallback(() => api.listTasks(meetingId).then(setTasks), [meetingId]);
  useEffect(() => {
    load();
  }, [load]);
  useEvent("tasks-changed", () => dragId === null && load());

  const open = tasks.filter((t) => !t.done && !hidden.has(t.id));
  const done = tasks.filter((t) => t.done && !hidden.has(t.id));

  const toggle = async (t: Task) => {
    setTasks((prev) => prev.map((x) => (x.id === t.id ? { ...x, done: !x.done } : x)));
    await api.setTaskDone(t.id, !t.done);
    load();
  };
  const save = async (t: Task, description: string, due: string | null) => {
    setTasks((prev) => prev.map((x) => (x.id === t.id ? { ...x, description, due } : x)));
    await api.updateTask(t.id, description, due);
  };
  const remove = async (t: Task) => {
    const ok = await confirmDialog({ title: "Delete this task?", message: `“${t.description}”` });
    if (!ok) return;
    setHidden((h) => new Set(h).add(t.id));
    undoToast(
      "Task deleted",
      () =>
        setHidden((h) => {
          const n = new Set(h);
          n.delete(t.id);
          return n;
        }),
      () => api.deleteTask(t.id).then(load),
    );
  };
  const add = async () => {
    if (!draft.trim()) return;
    await api.addTask(meetingId, draft.trim(), null);
    setDraft("");
    load();
  };

  // Drag & drop: reorder live while dragging, save on drop.
  const handlers = (t: Task) => ({
    draggable: true,
    onDragStart: (e: React.DragEvent) => {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(t.id));
      orderBeforeDrag.current = tasks;
      setDragId(t.id);
    },
    onDragOver: (e: React.DragEvent) => {
      if (dragId === null || dragId === t.id) return;
      e.preventDefault();
      setOverId(t.id);
      setTasks((prev) => {
        const from = prev.findIndex((x) => x.id === dragId);
        const to = prev.findIndex((x) => x.id === t.id);
        if (from < 0 || to < 0 || from === to) return prev;
        const next = [...prev];
        const [moved] = next.splice(from, 1);
        next.splice(to, 0, moved);
        return next;
      });
    },
    onDrop: (e: React.DragEvent) => e.preventDefault(),
    onDragEnd: async () => {
      const changed = orderBeforeDrag.current.map((x) => x.id).join() !== tasks.map((x) => x.id).join();
      setDragId(null);
      setOverId(null);
      if (changed) await api.reorderTasks(tasks.filter((x) => !x.done).map((x) => x.id));
    },
  });

  return (
    <div>
      {open.length === 0 && done.length === 0 ? (
        <div className="empty">No tasks yet. They appear here after a meeting or when you say “record tasks”.</div>
      ) : (
        <ul className="list stagger">
          {open.map((t, i) => (
            <TaskRow
              key={t.id}
              task={t}
              index={i}
              showMeeting={showMeeting}
              dragging={dragId === t.id}
              dropTarget={overId === t.id && dragId !== t.id}
              onToggle={() => toggle(t)}
              onSave={(d, due) => save(t, d, due)}
              onDelete={() => remove(t)}
              onOpenSource={onOpenSource && t.meeting_id ? () => onOpenSource(t) : undefined}
              dragHandlers={handlers(t)}
            />
          ))}
          {showDone &&
            done.map((t, i) => (
              <TaskRow
                key={t.id}
                task={t}
                index={i}
                showMeeting={showMeeting}
                dragging={false}
                dropTarget={false}
                onToggle={() => toggle(t)}
                onSave={(d, due) => save(t, d, due)}
                onDelete={() => remove(t)}
                onOpenSource={onOpenSource && t.meeting_id ? () => onOpenSource(t) : undefined}
                dragHandlers={{ draggable: false }}
              />
            ))}
        </ul>
      )}
      <div className="add-task">
        <input
          placeholder="Add a task…"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
        />
        <button className="primary" onClick={add} disabled={!draft.trim()}>
          Add
        </button>
      </div>
      {done.length > 0 && (
        <button className="link small" style={{ marginTop: 12 }} onClick={() => setShowDone(!showDone)}>
          {showDone ? "Hide" : "Show"} {done.length} completed
        </button>
      )}
    </div>
  );
}

export default function TasksView({ onOpenSource }: { onOpenSource: (t: Task) => void }) {
  return (
    <section className="page">
      <header className="page-header">
        <h1>My tasks</h1>
        <p>Everything assigned to you. Drag to reorder, double-click or use the pencil to edit.</p>
      </header>
      <TaskList showMeeting onOpenSource={onOpenSource} />
    </section>
  );
}
