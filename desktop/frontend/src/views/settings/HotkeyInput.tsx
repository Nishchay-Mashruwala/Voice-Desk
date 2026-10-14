import { useEffect, useState } from "react";
import { api } from "../../api";

const MODIFIERS = ["Control", "Shift", "Alt", "Meta"];

function heldModifiers(e: React.KeyboardEvent): string[] {
  return [e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", e.metaKey && "Super"].filter(Boolean) as string[];
}


/**
 * Click, then press 1–3 keys together: e.g. "F9", "Ctrl+Space", "Ctrl+Shift+Space".
 * (Global shortcuts need exactly one non-modifier key, plus up to two modifiers.)
 */
export default function HotkeyInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [capturing, setCapturing] = useState(false);
  const [preview, setPreview] = useState("");
  const [error, setError] = useState<string | null>(null);
  // A typing key alone (like "KeyR") would stop typing that key in other apps: the backend says.
  const [typingKey, setTypingKey] = useState(false);
  useEffect(() => {
    api
      .checkShortcut(value)
      .then((c) => setTypingKey(c.typing_key_alone))
      .catch(() => setTypingKey(false));
  }, [value]);
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
          const input = e.target as HTMLInputElement;
          const keys = [...mods, e.code].join("+");
          api.checkShortcut(keys).then((c) => {
            if (c.problem === "too_many_keys") return setError("Use at most 3 keys.");
            setError(null);
            onChange(keys);
            input.blur();
          });
        }}
      />
      {error && <span className="field-hint bad">{error}</span>}
      {!error && typingKey && (
        <span className="field-hint" style={{ color: "var(--warn)" }}>
          Heads up: “{value}” alone will stop typing that key in other apps. A function key (like F9) or a combo is safer.
        </span>
      )}
    </>
  );
}
