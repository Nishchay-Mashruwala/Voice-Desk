import { useEffect, useRef, useState } from "react";

interface Choice<T extends string> {
  label: string;
  value: T;
  className?: string;
}

interface Request {
  title: string;
  message: string;
  /** Left to right; the first is the safe choice (focused, and what Esc / clicking outside picks). */
  choices: Choice<string>[];
  resolve: (value: string) => void;
}

let show: ((r: Request) => void) | null = null;

/** Ask the user to pick one of a few choices. Resolves the first (safe) choice when dismissed. */
export function choiceDialog<T extends string>(opts: { title: string; message: string; choices: Choice<T>[] }): Promise<T> {
  return new Promise((resolve) => {
    const safe = opts.choices[0].value;
    if (!show) return resolve(window.confirm(opts.message) ? opts.choices[opts.choices.length - 1].value : safe);
    show({ ...opts, resolve: resolve as (v: string) => void });
  });
}

/** Ask before doing something destructive. Resolves true if the user confirms. */
export async function confirmDialog(opts: { title: string; message: string; confirmLabel?: string }): Promise<boolean> {
  const v = await choiceDialog({
    title: opts.title,
    message: opts.message,
    choices: [
      { label: "Cancel", value: "cancel" },
      { label: opts.confirmLabel ?? "Delete", value: "ok", className: "danger-solid" },
    ],
  });
  return v === "ok";
}

/**
 * Renders the dialog; mount once. Esc or clicking outside picks the safe
 * choice. Enter (or Space) acts on whichever button has focus — the safe one
 * at first — so a stray Enter never confirms something destructive.
 */
export function ConfirmHost() {
  const [req, setReq] = useState<Request | null>(null);
  const safeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    show = (r) =>
      setReq((prev) => {
        prev?.resolve(prev.choices[0].value);
        return r;
      });
    return () => {
      show = null;
    };
  }, []);

  const close = (value: string) => {
    req?.resolve(value);
    setReq(null);
  };

  useEffect(() => {
    if (!req) return;
    safeRef.current?.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") close(req.choices[0].value);
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [req]);

  if (!req) return null;
  return (
    <div className="dialog-backdrop" onMouseDown={(e) => e.target === e.currentTarget && close(req.choices[0].value)}>
      <div className="dialog" role="alertdialog" aria-modal="true" aria-labelledby="dialog-title">
        <h2 id="dialog-title">{req.title}</h2>
        <p>{req.message}</p>
        <div className="dialog-actions">
          {req.choices.map((c, i) => (
            <button key={c.value} ref={i === 0 ? safeRef : undefined} className={c.className} onClick={() => close(c.value)}>
              {c.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
