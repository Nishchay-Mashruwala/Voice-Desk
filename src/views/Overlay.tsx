import { invoke } from "@tauri-apps/api/core";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { useEffect, useRef, useState } from "react";
import { api, formatClock, useEvent, type EngineStatus, type SessionStatus } from "../api";
import logo from "../assets/logo.png";
import { useLite } from "../lite";
import { ChevronLeft, ListCheck, Pause, Play, Stop, X } from "../icons";

// Window sizes (logical px) for the two looks. Keep in sync with tauri.conf.json.
const FULL = { w: 214, h: 58 };
// Recording a meeting: just Stop, the timer and collapse.
const MEETING = { w: 150, h: 58 };
const MINI = { w: 58, h: 58 };
const COLLAPSED_KEY = "overlay-collapsed";

function readCollapsed(): boolean {
  try {
    return localStorage.getItem(COLLAPSED_KEY) === "1";
  } catch {
    return false;
  }
}

/**
 * Floating control bar shown while listening. No hover tooltips: Windows
 * draws them underneath this always-on-top window, where they show as stray text.
 *
 *   [stop] [pause/resume] [record tasks] [◀ collapse]
 * Collapsed, it's just the Voice Desk logo, glowing with your voice; click it
 * to expand. Both can be dragged anywhere. The window never takes keyboard focus.
 */
export default function Overlay() {
  const [status, setStatus] = useState<SessionStatus>({
    state: "idle",
    capturing: false,
    processing: 0,
    assistant_name: "Jarvis",
    listening_s: null,
    meeting: null,
    call_prompt: null,
    call_switch_s: null,
  });
  const [level, setLevel] = useState(0);
  const [collapsed, setCollapsed] = useState(readCollapsed);
  const [flash, setFlash] = useState<string | null>(null);
  const flashTimer = useRef(0);

  const [device, setDevice] = useState<string | undefined>();
  const [engine, setEngine] = useState<EngineStatus | null>(null);
  useEffect(() => {
    api.sessionStatus().then(setStatus);
    api.getSettings().then((s) => setDevice(s.device)).catch(() => setDevice("auto"));
    api.engineState().then(setEngine).catch(() => {});
  }, []);
  useEvent<SessionStatus>("session-status", setStatus);
  useEvent<EngineStatus>("engine-status", setEngine);
  useLite(device, engine);

  const showFlash = (msg: string) => {
    setFlash(msg);
    clearTimeout(flashTimer.current);
    flashTimer.current = window.setTimeout(() => setFlash(null), 2800);
  };
  // `short`: a version that fits the bar (the main window shows the full message).
  useEvent<{ message: string; short?: string }>("session-notice", (n) => showFlash(n.short ?? n.message));
  useEvent<{ count?: number; error?: string }>("capture-done", (d) =>
    showFlash(d.error ? "Couldn't create tasks" : `✓ ${d.count} task${d.count === 1 ? "" : "s"} added`),
  );

  // A call offer always shows in full, even when the bar is collapsed.
  const offer = status.call_prompt && !status.meeting ? status.call_prompt : null;
  const meeting = status.meeting;
  const small = collapsed && !offer;

  // Timer: time since the meeting recording (or listening) started. The
  // backend's clock is the truth; every status update re-syncs to it if this
  // one drifted (e.g. after sleep).
  const elapsed = meeting ? meeting.elapsed_s : status.listening_s;
  const timerKey = meeting ? `m${meeting.id}` : status.listening_s != null ? "listen" : null;
  const [now, setNow] = useState(Date.now());
  const started = useRef<{ key: string; at: number } | null>(null);
  useEffect(() => {
    if (timerKey == null || elapsed == null) {
      started.current = null;
      return;
    }
    const at = Date.now() - elapsed * 1000;
    const cur = started.current;
    if (!cur || cur.key !== timerKey || Math.abs(cur.at - at) > 1000) started.current = { key: timerKey, at };
    setNow(Date.now());
  }, [status]);
  useEffect(() => {
    if (timerKey == null) return;
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, [timerKey]);
  const time = timerKey != null ? formatClock((now - (started.current?.at ?? now)) / 1000) : "";
  // Listening when a call started: it becomes a meeting recording at this moment (✕ cancels).
  const switchAt = useRef<number | null>(null);
  useEffect(() => {
    switchAt.current = status.call_switch_s != null ? Date.now() + status.call_switch_s * 1000 : null;
  }, [status]);
  const switchIn = switchAt.current != null ? Math.max(0, Math.ceil((switchAt.current - now) / 1000)) : null;

  // Resize the window to fit the current look.
  useEffect(() => {
    const size = small ? MINI : meeting && !offer ? MEETING : FULL;
    invoke("overlay_resize", { width: size.w, height: size.h }).catch(() => {});
    try {
      localStorage.setItem(COLLAPSED_KEY, collapsed ? "1" : "0");
    } catch {
      /* private mode etc. — fine */
    }
  }, [small, !!meeting, !!offer]);

  const live = status.state !== "idle" || !!meeting;
  useEffect(() => {
    if (!live) return;
    const t = setInterval(async () => {
      const l = await api.audioLevels();
      setLevel(meeting ? Math.max(l.mic ?? 0, l.system ?? 0) : (l.listening ?? 0));
    }, 60);
    return () => clearInterval(t);
  }, [live, !!meeting]);

  /** Drag on movement; treat a still press as a click. */
  const dragOrClick = (onClick?: () => void) => (e: React.MouseEvent) => {
    if (e.button !== 0) return;
    const [x0, y0] = [e.screenX, e.screenY];
    const move = (m: MouseEvent) => {
      if (Math.abs(m.screenX - x0) + Math.abs(m.screenY - y0) > 4) {
        cleanup();
        getCurrentWindow().startDragging();
      }
    };
    const up = () => {
      cleanup();
      onClick?.();
    };
    const cleanup = () => {
      window.removeEventListener("mousemove", move);
      window.removeEventListener("mouseup", up);
    };
    window.addEventListener("mousemove", move);
    window.addEventListener("mouseup", up);
  };

  const name = status.assistant_name || "Jarvis";
  // Colours the whole bar: red while recording a meeting or tasks.
  const tone = meeting || status.capturing ? "capturing" : status.state;
  const amp = Math.min(1, Math.sqrt(level) * 5);
  const title = meeting
    ? "Recording meeting"
    : status.state === "starting"
      ? "Starting…"
      : status.capturing
        ? `Recording tasks — say “${name}, tasks recorded” to finish`
        : status.state === "paused"
          ? "Paused — not typing"
          : "Listening — typing at your cursor";

  if (offer) {
    return (
      <div className="ov-wrap">
        <div className="ov-bar capturing" aria-label={`${offer} call — transcribe it?`} onMouseDown={dragOrClick()}>
          <button className="ov-offer" onClick={() => api.callPromptAccept()}>
            {switchIn != null ? `Meeting in ${switchIn} s` : "Transcribe Meeting"}
          </button>
          <button className="ov-btn ghost" aria-label="Not this call" onClick={() => api.callPromptDismiss()}>
            <X size={14} />
          </button>
        </div>
      </div>
    );
  }

  if (small) {
    return (
      <div className="ov-wrap">
        <div
          className={`ov-mini ${tone}`}
          aria-label={`${title}. Click to expand, drag to move.`}
          onMouseDown={dragOrClick(() => setCollapsed(false))}
        >
          <span className="ov-ring" style={{ transform: `scale(${1 + amp * 0.5})`, opacity: 0.2 + amp * 0.7 }} />
          <img className="ov-logo-img" src={logo} alt="" draggable={false} />
          {status.state === "starting" && <span className="ov-mini-spinner spinner" />}
          {status.processing > 0 && <span className="ov-badge" />}
          {time && <span className="ov-mini-time">{time}</span>}
        </div>
      </div>
    );
  }

  return (
    <div className="ov-wrap">
      <div
        className={`ov-bar ${tone}`}
        aria-label={title}
        style={{ "--level": amp } as React.CSSProperties}
        onMouseDown={dragOrClick()}
      >
        {flash ? (
          <span className="ov-flash">{flash}</span>
        ) : meeting ? (
          <>
            <button className="ov-btn stop" aria-label="Stop and find tasks" onClick={() => api.stopMeeting().catch((e) => showFlash(`Couldn't stop: ${e}`))}>
              <Stop size={13} />
            </button>
            <span className="ov-timer">
              <span className="ov-rec-dot" />
              {time}
            </span>
          </>
        ) : (
          <>
            <button className="ov-btn stop" aria-label="Stop listening" onClick={() => api.sessionStop().catch((e) => showFlash(`Couldn't stop: ${e}`))}>
              {status.state === "starting" ? <span className="spinner" /> : <Stop size={13} />}
            </button>
            <button
              className="ov-btn"
              aria-label={status.state === "paused" ? "Resume typing" : "Pause typing"}
              disabled={status.capturing || status.state === "stopping" || status.state === "starting"}
              onClick={() => api.sessionSetWriting(status.state === "paused")}
            >
              {status.state === "paused" ? <Play size={14} /> : <Pause size={14} />}
            </button>
            <button
              className={`ov-btn ${status.capturing ? "on" : ""}`}
              aria-label={status.capturing ? "Finish recording tasks" : "Record tasks"}
              disabled={status.state === "stopping" || status.state === "starting"}
              onClick={() => api.captureToggle()}
            >
              <ListCheck size={15} />
            </button>
            <span className="ov-timer listen">{time}</span>
          </>
        )}
        <button className="ov-btn ghost" aria-label="Minimise to the logo" onClick={() => setCollapsed(true)}>
          <ChevronLeft size={15} />
        </button>
      </div>
    </div>
  );
}
