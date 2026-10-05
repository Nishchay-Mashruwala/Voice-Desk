import { useState } from "react";

const MODIFIERS = ["Control", "Shift", "Alt", "Meta"];

function heldModifiers(e: React.KeyboardEvent): string[] {
  return [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Super"].filter(Boolean) as string[];
}

/** Keys you'd lose for normal typing if used alone as a global shortcut. */
function isTypingKey(code: string): boolean {
  return /^(Key[A-Z]|Digit\d|Space|Enter|Backspace|Tab|Minus|Equal|Bracket\w+|Semicolon|Quote|Comma|Period|Slash|Backslash|Backquote)$/.test(code);
}

/**
 * Click, then press 1–3 keys together: e.g. "F9", "Ctrl+Space", "Ctrl+Shift+Space".
 * (Global shortcuts need exactly one non-modifier key, plus up to two modifiers.)
 */
export default function HotkeyInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [capturing, setCapturing] = useState(false);
  const [preview, setPreview] = useState("");
  const [error, setError] = useState<string | null>(null);
  const single = !value.includes("+");
  return (
    <>
      <input
        readOnly
        className={`hotkey-input ${capturing ? "capturing" : ""}`}
        value={capturing ? preview || "Press 1–3 keys…" : value}
        onFocus={() => {
          setCapturing(true);
          setPreview("");
          setError(null);
        }}
        onBlur={() => setCapturing(false)}
        onKeyUp={(e) => setPreview(heldModifiers(e).map((m) => m + " + ").join(""))}
        onKeyDown={(e) => {
          e.preventDefault();
          if (e.key === "Escape") return (e.target as HTMLInputElement).blur();
          const mods = heldModifiers(e);
          if (MODIFIERS.includes(e.key)) {
            setPreview(mods.map((m) => m + " + ").join("") + "…");
            return;
          }
          const keys = [...mods, e.code];
          if (keys.length > 3) {
            setError("Use at most 3 keys.");
            return;
          }
          setError(null);
          onChange(keys.join("+"));
          (e.target as HTMLInputElement).blur();
        }}
      />
      {error && <span className="field-hint bad">{error}</span>}
      {!error && single && isTypingKey(value) && (
        <span className="field-hint" style={{ color: "var(--warn)" }}>
          Heads up: “{value}” alone will stop typing that key in other apps. A function key (like F9) or a combo is safer.
        </span>
      )}
    </>
  );
}
