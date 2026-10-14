import type { Settings } from "../../api";
import { Check } from "../../icons";

/** Change one setting in the draft (saved with the save bar). */
export type SetSetting = <K extends keyof Settings>(k: K, v: Settings[K]) => void;

export function Field({
  label,
  hint,
  full,
  id,
  children,
}: {
  label: string;
  hint?: React.ReactNode;
  full?: boolean;
  /** Lets Setup's to-do list jump here. */
  id?: string;
  children: React.ReactNode;
}) {
  return (
    <label className={`field ${full ? "full" : ""}`} id={id}>
      <span className="field-label">{label}</span>
      {children}
      {hint && <span className="field-hint">{hint}</span>}
    </label>
  );
}

/** An on/off switch; works with the keyboard too (Tab to it, Space or Enter flips it). */
export function Toggle({ on, onChange, label, hint }: { on: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <div
      className="toggle-row full"
      role="switch"
      aria-checked={on}
      aria-label={label}
      tabIndex={0}
      onClick={() => onChange(!on)}
      onKeyDown={(e) => {
        if (e.key === " " || e.key === "Enter") {
          e.preventDefault(); // Space would scroll the page
          onChange(!on);
        }
      }}
    >
      <span className={`switch ${on ? "on" : ""}`} />
      <span>
        <span className="field-label">{label}</span>
        {hint && <span className="field-hint" style={{ display: "block" }}>{hint}</span>}
      </span>
    </div>
  );
}

export function CheckItem({ ok, title, detail, children }: { ok: boolean; title: string; detail: React.ReactNode; children?: React.ReactNode }) {
  return (
    <div className="check-item">
      <span className={`check-icon ${ok ? "ok" : "todo"}`}>{ok ? <Check size={14} strokeWidth={2.6} /> : "!"}</span>
      <div className="grow">
        <div className="field-label">{title}</div>
        <div className="small muted">{detail}</div>
      </div>
      {children}
    </div>
  );
}

/** A progress bar; `pct` below 0 means "working, amount unknown". */
export function ProgressBar({ pct, width }: { pct: number; width?: number }) {
  return (
    <div className="progress-track" style={width ? { width } : undefined}>
      <div className={`progress-fill ${pct < 0 ? "indeterminate" : ""}`} style={{ width: `${Math.max(2, pct)}%` }} />
    </div>
  );
}
