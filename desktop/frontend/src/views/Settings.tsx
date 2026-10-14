import { getVersion } from "@tauri-apps/api/app";
import { useCallback, useEffect, useState } from "react";
import {
  api,
  useEvent,
  type CallApps,
  type CommandPhrases,
  type Hardware,
  type LlmPull,
  type ModelDownload,
  type ModelInfo,
  type ModelOptions,
  type SetupChoices,
  type SetupPlan,
  type SettingsRules,
  type SetupStatus,
  type Settings,
} from "../api";
import { Check, ChevronDown, Refresh } from "../icons";
import { hardwareOnce } from "../lite";
import { downloadPct, downloadText } from "../modelDownload";
import { modelName } from "../models";
import { callAppsText, engineDownloadText, taskModelLabel } from "../wording";
import { toast } from "../toast";
import { checkForUpdates } from "../updates";
import { CheckItem, Field, ProgressBar, Toggle } from "./settings/common";
import GettingReady, { pullText } from "./settings/GettingReady";
import HotkeyInput from "./settings/HotkeyInput";
import LanguagePicker, { HfToken } from "./settings/LanguagePicker";
import ModelPicker from "./settings/ModelPicker";
import { DataFolders, DiskNow, DownloadedModels, MemoryNow } from "./settings/Storage";
import VoiceEnrollment from "./settings/VoiceSetup";

/** What App needs to stop you leaving Settings with unsaved edits. */
export interface SettingsGuard {
  dirty: boolean;
  /** Saves the edits; false if saving failed (then stay on the page). */
  save: () => Promise<boolean>;
}

/** Scroll to a setting further down (from Setup's to-do list) and put the cursor in it. */
function jumpTo(id: string) {
  const el = document.getElementById(id);
  el?.scrollIntoView({ block: "center", behavior: "smooth" });
  el?.querySelector<HTMLElement>("input, button")?.focus({ preventScroll: true });
}

/**
 * Settings, in the order people need them: Setup (downloads and what's left
 * to do), Basics, Meetings, and Advanced (collapsed; most people never need it).
 * Edits are a draft until saved with the save bar.
 */
export default function SettingsView({
  settings,
  onSaved,
  guard,
  download,
}: {
  settings: Settings;
  onSaved: (s: Settings) => void;
  guard: React.MutableRefObject<SettingsGuard | null>;
  /** A speech model the engine is downloading now. */
  download: ModelDownload | null;
}) {
  const [s, setS] = useState<Settings>(settings);
  const [setup, setSetup] = useState<SetupStatus | null>(null);
  const [pull, setPull] = useState<LlmPull | null>(null);
  const [advanced, setAdvanced] = useState(false);
  const dirty = JSON.stringify(s) !== JSON.stringify(settings);

  const refreshSetup = useCallback(
    () =>
      api
        .setupStatus()
        .then(setSetup)
        .catch((e) => toast(`Couldn't check the setup: ${e}`)),
    [],
  );
  useEffect(() => {
    refreshSetup();
  }, [refreshSetup]);
  useEvent("engine-status", refreshSetup);
  useEvent<LlmPull>("llm-pull", setPull);
  // A download running in the background (started on an earlier visit): check
  // now and then so the page notices when it's done.
  const busy = !!setup && (setup.installing || setup.pulling);
  useEffect(() => {
    if (!busy) {
      setPull(null);
      return;
    }
    const t = setInterval(() => !document.hidden && refreshSetup(), 3000);
    return () => clearInterval(t);
  }, [busy, refreshSetup]);

  const [callApps, setCallApps] = useState<CallApps | null>(null);
  const [version, setVersion] = useState("");
  const [hw, setHw] = useState<Hardware | null>(null);
  useEffect(() => {
    getVersion().then(setVersion).catch(() => {});
    api.watchedCallApps().then(setCallApps).catch(() => {});
    hardwareOnce().then(setHw);
  }, []);

  // Models on disk: fetched once and shared by the pickers ("Downloaded") and
  // the Downloaded models list, then refreshed after a delete or save.
  const [models, setModels] = useState<ModelInfo[] | null>(null);
  const refreshModels = useCallback(
    () =>
      api
        .modelsInfo()
        .then(setModels)
        .catch(() => setModels([])),
    [],
  );
  useEffect(() => {
    refreshModels();
  }, [refreshModels]);

  // What the pickers offer and what setup would download, for the settings on
  // screen (maybe not saved yet): both decided by the backend.
  const [options, setOptions] = useState<ModelOptions | null>(null);
  const [choices, setChoices] = useState<SetupChoices>({ nvidia: true, indic: true });
  const [plan, setPlan] = useState<SetupPlan | null>(null);
  const [phrases, setPhrases] = useState<CommandPhrases | null>(null);
  const draftKey = JSON.stringify(s);
  useEffect(() => {
    let alive = true;
    api
      .modelOptions(s)
      .then((o) => alive && setOptions(o))
      .catch(() => {});
    api
      .setupPlan(s, choices)
      .then((p) => alive && setPlan(p))
      .catch(() => {});
    api
      .commandPhrases(s)
      .then((p) => alive && setPhrases(p))
      .catch(() => {});
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [draftKey, choices, setup, models]);

  const set = <K extends keyof Settings>(k: K, v: Settings[K]) => setS((prev) => ({ ...prev, [k]: v }));

  // Limits for the sliders and number fields (the backend enforces them when saving).
  const [rules, setRules] = useState<SettingsRules | null>(null);
  useEffect(() => {
    api.settingsRules().then(setRules).catch(() => {});
  }, []);

  const save = async (): Promise<boolean> => {
    if (!dirty) return true;
    try {
      // Saved as the backend checked and tidied them.
      const saved = await api.saveSettings(s);
      setS(saved);
      onSaved(saved);
      toast("Settings saved");
      refreshSetup();
      refreshModels();
      return true;
    } catch (e) {
      toast(`Couldn't save settings: ${e}`);
      return false;
    }
  };
  // Let App ask before leaving with unsaved edits.
  useEffect(() => {
    guard.current = { dirty, save };
  });
  useEffect(
    () => () => {
      guard.current = null;
    },
    [guard],
  );

  const engine = setup?.engine;
  const taskReady = !!setup && setup.llm.installed && setup.llm.model_ready;
  const taskLabel = setup ? taskModelLabel(setup.llm.model, setup.llm.size_gb) : "";
  const showGettingReady = !!setup && !!plan && (plan.steps.length > 0 || setup.installing || setup.pulling);

  const speechDetail = !setup
    ? ""
    : download
      ? `${downloadText(download)} (first use only)`
      : setup.installing
        ? "Being set up — see Getting ready above."
        : !setup.engine_installed
          ? setup.engine_partial
            ? "Already on this computer — its setup needs finishing (see Getting ready above)."
            : "Not downloaded yet — see Getting ready above."
          : engine?.state === "ready"
            ? `Ready: ${engine.model} on ${engine.device === "cuda" ? "GPU" : "CPU"}`
            : engine?.state === "sleeping"
              ? "Sleeping to save memory — wakes up when you start listening."
              : engine?.state === "downloading"
                ? engineDownloadText(engine) || "Downloading the speech model…"
                : engine?.state === "error"
                  ? engine.message
                  : "Loading…";

  // Things you set further down, listed here only while they still need doing.
  const todo: { id: string; title: string; detail: string }[] = [];
  if (setup && !setup.name_set) todo.push({ id: "set-name", title: "Your name", detail: "Needed to know which tasks are yours." });
  if (setup && !setup.voice_profile)
    todo.push({ id: "set-voice", title: "Your voice", detail: "Optional: train it so nobody else can control Voice Desk." });
  if (plan?.needs_hf_token)
    todo.push({ id: "set-hf", title: "Hindi/Gujarati model", detail: "Needs a free Hugging Face token to download." });

  return (
    <section className="page">
      <header className="page-header">
        <h1>Settings</h1>
        <p>Everything runs on this computer. Nothing you say leaves it.</p>
      </header>

      {/* Setup -------------------------------------------------------------- */}
      <div className="card">
        <div className="card-title">
          <h2>Setup</h2>
          <button className="ghost icon" title="Check again" onClick={refreshSetup}>
            <Refresh size={15} />
          </button>
        </div>
        {!setup ? (
          <div className="row small muted">
            <span className="spinner dark" /> Checking…
          </div>
        ) : (
          <div className="checklist">
            {showGettingReady && plan && (
              <GettingReady
                setup={setup}
                plan={plan}
                choices={choices}
                onChoices={setChoices}
                ensureSaved={save}
                onDone={() => {
                  refreshSetup();
                  refreshModels();
                }}
              />
            )}
            <CheckItem ok={setup.engine_installed && !setup.installing && engine?.state !== "error"} title="Speech engine" detail={speechDetail}>
              {download && <ProgressBar pct={downloadPct(download) ?? -1} width={160} />}
              {engine?.state === "error" && (
                <button onClick={() => api.engineRestart()}>
                  <Refresh size={14} /> Retry
                </button>
              )}
            </CheckItem>
            <CheckItem
              ok={taskReady && !setup.pulling}
              title={`Task AI (${taskLabel})`}
              detail={
                setup.pulling && pull
                  ? `${pullText(pull)}${pull.pct >= 0 ? ` — ${Math.round(pull.pct)}%` : "…"}`
                  : taskReady
                    ? `Ready: ${taskLabel}`
                    : "Not downloaded yet — see Getting ready above."
              }
            />
            {todo.map((t) => (
              <CheckItem key={t.id} ok={false} title={t.title} detail={t.detail}>
                <button onClick={() => jumpTo(t.id)}>Set it below</button>
              </CheckItem>
            ))}
          </div>
        )}
      </div>

      {/* Basics ------------------------------------------------------------- */}
      <div className="card">
        <div className="card-title">
          <h2>Basics</h2>
        </div>
        <div className="settings-grid">
          <h3 className="full settings-sub">About you</h3>
          <Field label="Your name" hint="How people say your name in meetings." id="set-name">
            <input value={s.user_name} onChange={(e) => set("user_name", e.target.value)} placeholder="e.g. Nishchay" />
          </Field>
          <Field label="Other names people call you" hint="Nicknames or spellings, comma separated.">
            <input value={s.aliases} onChange={(e) => set("aliases", e.target.value)} />
          </Field>

          <h3 className="full settings-sub">Shortcut</h3>
          <Field label="Shortcut" hint="Click, then press 1–3 keys together (Esc to cancel).">
            <HotkeyInput value={s.dictation_hotkey} onChange={(v) => set("dictation_hotkey", v)} />
          </Field>
          <div className="field">
            <span className="field-label">The shortcut starts</span>
            <div className="segmented" role="radiogroup" aria-label="The shortcut starts">
              {(
                [
                  ["listen", "Listening (typing)"],
                  ["meeting", "Meeting recording"],
                ] as const
              ).map(([value, label]) => (
                <button
                  key={value}
                  type="button"
                  role="radio"
                  aria-checked={s.shortcut_starts === value}
                  className={s.shortcut_starts === value ? "on" : ""}
                  onClick={() => set("shortcut_starts", value)}
                >
                  {label}
                </button>
              ))}
            </div>
            <span className="field-hint">
              {s.shortcut_starts === "meeting"
                ? "Records you and the computer's audio, then finds tasks. If you're already listening, that becomes the start of the meeting. Press twice to stop. The tray and the mic button still start listening."
                : "Types what you say wherever your cursor is. During a call, the shortcut records the meeting instead."}
            </span>
          </div>
          <Field
            label="How the shortcut works"
            hint={s.shortcut_starts === "meeting" && s.dictation_mode === "hold" ? "For a meeting, push-to-talk works as press to start, press to stop." : undefined}
          >
            <select value={s.dictation_mode} onChange={(e) => set("dictation_mode", e.target.value as Settings["dictation_mode"])}>
              <option value="toggle">Single press — press to start, press to stop</option>
              <option value="double">Double press — press twice quickly to start / stop</option>
              <option value="long">Long press — hold to start / stop</option>
              <option value="hold">Push-to-talk — listen only while held</option>
            </select>
          </Field>
          {s.dictation_mode === "long" && rules && (
            <Field label={`Hold for: ${s.long_press_s.toFixed(1)} seconds`} hint="How long to hold the shortcut before listening starts or stops.">
              <input
                type="range"
                min={rules.limits.long_press_s.min}
                max={rules.limits.long_press_s.max}
                step={rules.limits.long_press_s.step}
                value={s.long_press_s}
                onChange={(e) => set("long_press_s", Number(e.target.value))}
              />
            </Field>
          )}
          <Field label="How text is inserted">
            <select value={s.insert_method} onChange={(e) => set("insert_method", e.target.value as Settings["insert_method"])}>
              <option value="paste">Paste (fast; clipboard is restored)</option>
              <option value="type">Type keystrokes (slower; never touches clipboard)</option>
            </select>
          </Field>
          <Field
            label={`Pause before typing: ${(s.silence_ms / 1000).toFixed(1)}s`}
            hint="Shorter = faster text. Longer = whole sentences, which the speech model understands better (0.8s recommended)."
          >
            <input
              type="range"
              min={rules?.limits.silence_ms.min}
              max={rules?.limits.silence_ms.max}
              step={rules?.limits.silence_ms.step}
              value={s.silence_ms}
              onChange={(e) => set("silence_ms", Number(e.target.value))}
            />
          </Field>

          <h3 className="full settings-sub">Languages</h3>
          <LanguagePicker s={s} set={set} order={rules?.limits.languages ?? []} indicModelGb={options?.indic_model_gb ?? null} />
          {plan?.uses_indic_model && <HfToken s={s} set={set} />}

          <h3 className="full settings-sub">Your voice</h3>
          <p className="small muted full">
            Read a short passage (about 15 seconds) so Voice Desk recognises you. Then commands spoken by other people — in the
            room or on a call — are ignored.
          </p>
          <VoiceEnrollment onChange={refreshSetup} seconds={rules?.limits.voice_training_s ?? null} />
          <Toggle on={s.voice_lock} onChange={(v) => set("voice_lock", v)} label="Only my voice can give commands" hint="Recommended. Needs a trained voice." />
          <Toggle
            on={s.only_my_voice}
            onChange={(v) => set("only_my_voice", v)}
            label="Only type what I say"
            hint="Ignore other voices near your microphone (open offices)."
          />

          <h3 className="full settings-sub">Voice commands</h3>
          <Field label="Assistant name" hint={phrases ? `Say it before every command, e.g. “${phrases.assistant_name}, ${phrases.pause}”.` : undefined} full>
            <input value={s.assistant_name} onChange={(e) => set("assistant_name", e.target.value)} placeholder={rules?.defaults.assistant_name} />
          </Field>
          {(
            [
              ["cmd_pause", "Pause typing", "Keeps listening for commands but stops typing."],
              ["cmd_resume", "Resume typing", ""],
              ["cmd_record_tasks", "Start recording tasks", "In a call: finds tasks others give you. Alone: turns what you say into to-dos."],
              ["cmd_tasks_recorded", "Finish recording tasks", "Creates the tasks and keeps listening."],
              ["cmd_stop", "Stop listening", ""],
            ] as const
          ).map(([key, label, hint]) => (
            <Field key={key} label={label} hint={hint || "Comma-separate alternatives."}>
              <input value={s[key]} onChange={(e) => set(key, e.target.value)} />
            </Field>
          ))}
        </div>
      </div>

      {/* Meetings ----------------------------------------------------------- */}
      <div className="card">
        <div className="card-title">
          <h2>Meetings</h2>
        </div>
        <div className="settings-grid">
          <Toggle
            on={s.detect_meetings}
            onChange={(v) => set("detect_meetings", v)}
            label="Detect meetings"
            hint={`When a call starts, the floating bar offers to transcribe it; your shortcut starts it too (✕ means not this call). Browsers count only on a call site (Meet, Zoom, Teams, WhatsApp…). Watches ${callApps ? callAppsText(callApps) : "call apps"}.`}
          />
          <Toggle
            on={s.auto_stop_meetings}
            onChange={(v) => set("auto_stop_meetings", v)}
            label="Stop meetings automatically"
            hint="When the call ends, or after 3 minutes with nobody speaking. The shortcut asks for a second press before stopping."
          />
          <div className="field full">
            <span className="field-label">Opening a task's recording</span>
            <span className="field-hint">Click a task's source in My tasks to hear where it was said.</span>
            <div className="segmented">
              {[5, 0].map((n) => (
                <button key={n} type="button" className={s.task_jump_lead_s === n ? "on" : ""} onClick={() => set("task_jump_lead_s", n)}>
                  {n === 0 ? "Start right at the task" : `Start ${n} seconds before`}
                </button>
              ))}
            </div>
          </div>
          {options && (
            <ModelPicker
              label="Task AI model"
              hint="Finds your tasks in recordings. Runs on this computer, only while finding tasks, and frees its memory a minute later. Auto: the 4B, unless the computer has under 6 GB of RAM. A new choice is downloaded from Setup above."
              options={options.task}
              selected={options.task_selected}
              autoNote={modelName(options.task_auto)}
              per="meeting"
              onChange={(id) => set("llm_model", id)}
            />
          )}
        </div>
      </div>

      {/* Advanced (collapsed) ----------------------------------------------- */}
      <div className="card">
        <button
          type="button"
          className="card-title collapse-head"
          aria-expanded={advanced}
          onClick={() => setAdvanced((v) => !v)}
        >
          <h2 className="grow">Advanced</h2>
          <span className="small muted">Processor, speech model, memory, storage</span>
          <ChevronDown size={16} className={`collapse-chevron ${advanced ? "open" : ""}`} />
        </button>
        {/* Rendered only when open: the memory panel polls while it's on screen. */}
        {advanced && (
          <div className="settings-grid">
            <h3 className="full settings-sub">Speech recognition</h3>
            <Field
              label="Processor"
              hint={
                hw
                  ? `Used for speech and the task AI; CPU only also keeps the app's window off the GPU (after a restart). ${hw.cores} CPU cores (Voice Desk uses up to ${hw.threads}), ` +
                    `${hw.ram_total_gb.toFixed(0)} GB RAM` +
                    (hw.gpus.length
                      ? "."
                      : navigator.userAgent.includes("Mac")
                        ? ". Auto lets the task AI and speaker detection use the Mac's GPU; speech runs on the CPU."
                        : ", no NVIDIA GPU found — the CPU is used.")
                  : "Used for speech and the task AI; CPU only also keeps the app's window off the GPU (after a restart)."
              }
            >
              <select value={s.device} onChange={(e) => set("device", e.target.value)}>
                <option value="auto">Auto — picks for this computer</option>
                {hw?.gpus.map((g) => (
                  <option key={g.index} value={`cuda:${g.index}`}>
                    GPU: {g.name} ({g.total_gb.toFixed(0)} GB)
                  </option>
                ))}
                {/* Older setting, or a GPU that's no longer connected. */}
                {s.device.startsWith("cuda") && !hw?.gpus.some((g) => `cuda:${g.index}` === s.device) && (
                  <option value={s.device}>NVIDIA GPU</option>
                )}
                <option value="cpu">CPU only</option>
              </select>
            </Field>
            <Field label="Vocabulary" hint="Names and jargon to spell right, comma separated. Your name and the assistant name are included automatically.">
              <input value={s.vocabulary} onChange={(e) => set("vocabulary", e.target.value)} placeholder="Priya, Tauri, OKRs" />
            </Field>
            <Field
              label="Leave out"
              hint="Words and phrases never written down — in typed text, Listen history and meeting transcripts — comma separated. Whole words only, any capitals; a repeated word (“the the”) becomes one. Applies to what you say from now on."
            >
              <input value={s.omit_words} onChange={(e) => set("omit_words", e.target.value)} placeholder="umm, uh, the the" />
            </Field>
            {options && (
              <ModelPicker
                label="Accuracy (speech model)"
                hint="Auto: on a GPU, large-v3-turbo for English only; medium when Hindi/Gujarati are written as spoken (IndicConformer writes them, using less GPU memory); large-v3 when translating them. On the CPU, small (base under 6 GB of RAM). A new choice downloads when Voice Desk next starts listening."
                options={options.speech}
                selected={options.speech_selected}
                autoNote={engine?.state === "ready" && engine.model ? `${engine.model} on the ${engine.device === "cuda" ? "GPU" : "CPU"}` : ""}
                per="minute of speech"
                onChange={(id) => set("whisper_model", id)}
              />
            )}

            <h3 className="full settings-sub">Memory &amp; storage</h3>
            <Field label="Free memory after idle (minutes)" hint="The speech engine shuts down when unused, and restarts when you talk. 0 = never.">
              <input
                type="number"
                min={rules?.limits.unload_after_min.min}
                value={s.unload_after_min}
                onChange={(e) => set("unload_after_min", Math.max(rules?.limits.unload_after_min.min ?? 0, Number(e.target.value)))}
              />
            </Field>
            <Field label="Keep recordings for (days)" hint="Older recordings are deleted; their text stays. 0 = keep forever.">
              <input
                type="number"
                min={rules?.limits.keep_audio_days.min}
                value={s.keep_audio_days}
                onChange={(e) => set("keep_audio_days", Math.max(rules?.limits.keep_audio_days.min ?? 0, Number(e.target.value)))}
              />
            </Field>
            <MemoryNow />
            <DiskNow models={models} />
            <DownloadedModels models={models} onChanged={refreshModels} />
            <DataFolders />
            <Toggle
              on={s.close_to_tray}
              onChange={(v) => set("close_to_tray", v)}
              label="Keep running in the tray when the window is closed"
              hint="Off: closing Voice Desk also stops the task AI and the speech engine. On: the shortcut keeps working in the background."
            />
          </div>
        )}
      </div>

      <div className="save-bar">
        <button className="primary" onClick={save} disabled={!dirty}>
          <Check size={15} /> Save settings
        </button>
        <span className="small muted">{dirty ? "You have unsaved changes." : "All changes saved."}</span>
      </div>
      <div className="card">
        <div className="card-title">
          <h2>About</h2>
        </div>
        <div className="row wrap">
          <span className="grow small muted">Voice Desk {version} · updates are checked when it starts</span>
          <button onClick={() => checkForUpdates(false)}>
            <Refresh size={14} /> Check for updates
          </button>
        </div>
      </div>
    </section>
  );
}
