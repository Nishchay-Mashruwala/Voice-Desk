import { useEffect, useRef, useState } from "react";
import { useEvent, type ModelDownload } from "./api";
import { gb } from "./models";

/** How often the progress shown may change: the engine reports many times a second. */
const THROTTLE_MS = 500;
/** No news for this long: the download finished (or stopped), stop showing it. */
const STALE_MS = 8000;

/**
 * The speech/voice/Gujarati/speaker model the engine is downloading now, or
 * null. Updates at most twice a second; clears itself when done.
 */
export function useModelDownload(): ModelDownload | null {
  const [shown, setShown] = useState<ModelDownload | null>(null);
  const last = useRef(0);
  const stale = useRef(0);

  useEvent<ModelDownload>("model-download", (d) => {
    clearTimeout(stale.current);
    const finished = d.total_mb != null && d.done_mb >= d.total_mb;
    if (finished) {
      setShown(null);
      return;
    }
    stale.current = window.setTimeout(() => setShown(null), STALE_MS);
    const now = Date.now();
    if (now - last.current < THROTTLE_MS) return;
    last.current = now;
    setShown(d);
  });
  // The engine is ready or asleep: whatever was downloading is done.
  useEvent<{ state: string }>("engine-status", (e) => {
    if (e.state === "ready" || e.state === "sleeping" || e.state === "error") {
      clearTimeout(stale.current);
      setShown(null);
    }
  });
  useEffect(() => () => clearTimeout(stale.current), []);
  return shown;
}

/** Percent done, or null when the size isn't known. */
export function downloadPct(d: ModelDownload): number | null {
  return d.total_mb ? Math.min(100, Math.round((d.done_mb / d.total_mb) * 100)) : null;
}

/** "Downloading speech model — 42% of 1.6 GB" / "— 310 MB". */
export function downloadText(d: ModelDownload): string {
  const pct = downloadPct(d);
  const amount = pct != null && d.total_mb ? `${pct}% of ${gb(d.total_mb / 1000)}` : gb(d.done_mb / 1000);
  return `Downloading ${d.what} — ${amount}`;
}
