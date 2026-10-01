import { useEffect, useState } from "react";
import { api, useEvent, type EngineStatus, type SessionStatus, type Settings, type SourceFocus, type Task } from "./api";
import logo from "./assets/logo.png";
import { Gear, ListCheck, Mic, Refresh, Users } from "./icons";
import { ConfirmHost } from "./confirm";
import { toast, ToastHost } from "./toast";
import ListenView from "./views/Listen";
import MeetingsView from "./views/Meetings";
import SettingsView from "./views/Settings";
import TasksView from "./views/Tasks";

type Tab = "listen" | "meetings" | "tasks" | "settings";

const TABS: { id: Tab; label: string; Icon: typeof Mic }[] = [
  { id: "listen", label: "Listen", Icon: Mic },
  { id: "meetings", label: "Meetings", Icon: Users },
  { id: "tasks", label: "My tasks", Icon: ListCheck },
  { id: "settings", label: "Settings", Icon: Gear },
];

function engineLabel(e: EngineStatus): string {
  switch (e.state) {
    case "ready":
      return `Ready · ${e.device === "cuda" ? "GPU" : "CPU"}`;
    case "loading":
      return "Loading speech model…";
    case "sleeping":
      return "Sleeping · wakes when you talk";
    default:
      return "Speech engine needs attention";
  }
}

export default function App() {
  const [tab, setTab] = useState<Tab>("listen");
  const [settings, setSettings] = useState<Settings | null>(null);
  const [engine, setEngine] = useState<EngineStatus>({ state: "loading" });
  const [session, setSession] = useState<SessionStatus | null>(null);
  const [openTasks, setOpenTasks] = useState(0);
  const [focus, setFocus] = useState<SourceFocus | undefined>();

  const go = (t: Tab) => {
    setFocus(undefined);
    setTab(t);
  };
  /** Show a recording on its page, optionally playing from a task's quote. */
  const open = (f: Omit<SourceFocus, "nonce">) => {
    setFocus({ ...f, nonce: Date.now() });
    setTab(f.meetingId != null ? "meetings" : "listen");
  };
  // A task's source tag: open the recording just before the task was said.
  // Meetings open on the Meetings page; everything said while listening on Listen.
  const openSource = (t: Task) => {
    const at = { quote: t.quote, leadS: settings?.task_jump_lead_s ?? 5, play: true };
    if (t.meeting_kind === "meeting" && t.meeting_id != null) open({ ...at, meetingId: t.meeting_id });
    else if (t.dictation_id != null) open({ ...at, dictationId: t.dictation_id });
    else toast("The recording this task came from is no longer available");
  };
  const openMeeting = (id: number) => open({ meetingId: id, quote: null, leadS: 0, play: false });
  const openDictation = (id: number) => open({ dictationId: id, quote: null, leadS: 0, play: false });

  const countTasks = () => api.listTasks().then((t) => setOpenTasks(t.filter((x) => !x.done).length));

  useEffect(() => {
    api.getSettings().then((s) => {
      setSettings(s);
      if (!s.user_name) setTab("settings"); // first run: set up first
    });
    api.engineState().then(setEngine);
    api.sessionStatus().then(setSession);
    countTasks();
  }, []);

  useEvent<EngineStatus>("engine-status", setEngine);
  useEvent<SessionStatus>("session-status", setSession);
  useEvent("tasks-changed", countTasks);
  useEvent<{ message: string }>("session-notice", (n) => toast(n.message));
  useEvent<{ count?: number; error?: string }>("capture-done", (d) => {
    countTasks();
    toast(d.error ? `Couldn't create tasks: ${d.error}` : `${d.count} task${d.count === 1 ? "" : "s"} added from your recording`, {
      action: d.error ? undefined : { label: "View", run: () => go("tasks") },
    });
  });

  const live = session && session.state !== "idle";

  return (
    <div className="app">
      <nav className="sidebar">
        <div className="brand">
          <img className="brand-logo" src={logo} alt="" />
          <span className="nav-label">Voice Desk</span>
        </div>
        {TABS.map(({ id, label, Icon }) => (
          <button key={id} className={`nav ${tab === id ? "active" : ""}`} onClick={() => go(id)} title={label}>
            <Icon size={18} />
            <span className="nav-label">{label}</span>
            {id === "listen" && live && <span className="dot live" style={{ marginLeft: "auto" }} />}
            {id === "tasks" && openTasks > 0 && <span className="nav-badge">{openTasks}</span>}
          </button>
        ))}
        <div className="sidebar-foot">
          <div className="chip-status" title={engine.message ?? `${engineLabel(engine)}${engine.model ? ` (${engine.model})` : ""}`}>
            <span className={`dot ${engine.state}`} />
            <span className="grow nav-label">{engineLabel(engine)}</span>
            {engine.state === "error" && (
              <button className="ghost icon" title="Restart speech engine" onClick={() => api.engineRestart()}>
                <Refresh size={14} />
              </button>
            )}
          </div>
        </div>
      </nav>
      <main className="content">
        {tab === "listen" && <ListenView key="listen" settings={settings} session={session} focus={focus} onOpenMeeting={openMeeting} />}
        {tab === "meetings" && <MeetingsView key="meetings" focus={focus} onOpenDictation={openDictation} />}
        {tab === "tasks" && <TasksView key="tasks" onOpenSource={openSource} />}
        {tab === "settings" && settings && <SettingsView key="settings" settings={settings} onSaved={setSettings} />}
      </main>
      <ToastHost />
      <ConfirmHost />
    </div>
  );
}
