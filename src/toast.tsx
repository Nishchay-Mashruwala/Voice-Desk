import { useEffect, useState } from "react";

interface Toast {
  id: number;
  message: string;
  action?: { label: string; run: () => void };
  onExpire?: () => void;
  /** How long it stays (ms). Undo toasts show a shrinking bar for this time. */
  duration: number;
}

type Listener = (t: Toast) => void;
const listeners = new Set<Listener>();
const actioned = new Set<number>();
let nextId = 1;

/** Show a small notification. `onExpire` runs if the action wasn't clicked. */
export function toast(
  message: string,
  opts: { action?: Toast["action"]; onExpire?: () => void; duration?: number } = {},
) {
  const t = { id: nextId++, message, ...opts, duration: opts.duration ?? 4500 };
  listeners.forEach((l) => l(t));
}

/** "X deleted · Undo" for 5 s; `commit` does the real delete if Undo isn't clicked. */
export function undoToast(message: string, undo: () => void, commit: () => void) {
  toast(message, { action: { label: "Undo", run: undo }, onExpire: commit, duration: 5000 });
}

export function ToastHost() {
  const [items, setItems] = useState<Toast[]>([]);

  useEffect(() => {
    const add: Listener = (t) => {
      setItems((prev) => [...prev.slice(-3), t]);
      setTimeout(() => {
        if (!actioned.delete(t.id)) t.onExpire?.();
        setItems((prev) => prev.filter((x) => x.id !== t.id));
      }, t.duration);
    };
    listeners.add(add);
    return () => {
      listeners.delete(add);
    };
  }, []);

  return (
    <div className="toast-stack">
      {items.map((t) => (
        <div key={t.id} className="toast">
          <span className="grow">{t.message}</span>
          {t.onExpire && <span className="toast-timer" style={{ animationDuration: `${t.duration}ms` }} />}
          {t.action && (
            <button
              className="link"
              onClick={() => {
                actioned.add(t.id);
                t.action!.run();
                setItems((prev) => prev.filter((x) => x.id !== t.id));
              }}
            >
              {t.action.label}
            </button>
          )}
        </div>
      ))}
    </div>
  );
}
