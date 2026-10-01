import { useEffect, useRef, useState } from "react";

interface Request {
  title: string;
  message: string;
  confirmLabel?: string;
  resolve: (ok: boolean) => void;
}

let show: ((r: Request) => void) | null = null;

/** Ask before doing something destructive. Resolves true if the user confirms. */
export function confirmDialog(opts: { title: string; message: string; confirmLabel?: string }): Promise<boolean> {
  return new Promise((resolve) => {
    if (!show) return resolve(window.confirm(opts.message));
    show({ ...opts, resolve });
  });
}

/** Renders the dialog; mount once. Esc or clicking outside cancels, Enter confirms. */
export function ConfirmHost() {
  const [req, setReq] = useState<Request | null>(null);
  const cancelRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    show = (r) =>
      setReq((prev) => {
        prev?.resolve(false);
        return r;
      });
    return () => {
      show = null;
    };
  }, []);

  const close = (ok: boolean) => {
    req?.resolve(ok);
    setReq(null);
  };

  useEffect(() => {
    if (!req) return;
    cancelRef.current?.focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === "Escape") close(false);
      if (e.key === "Enter") {
        e.preventDefault();
        close(true);
      }
    };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  });

  if (!req) return null;
  return (
    <div className="dialog-backdrop" onMouseDown={(e) => e.target === e.currentTarget && close(false)}>
      <div className="dialog" role="alertdialog" aria-modal="true" aria-labelledby="dialog-title">
        <h2 id="dialog-title">{req.title}</h2>
        <p>{req.message}</p>
        <div className="dialog-actions">
          <button ref={cancelRef} onClick={() => close(false)}>
            Cancel
          </button>
          <button className="danger-solid" onClick={() => close(true)}>
            {req.confirmLabel ?? "Delete"}
          </button>
        </div>
      </div>
    </div>
  );
}
