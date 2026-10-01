import { openUrl } from "@tauri-apps/plugin-opener";
import { useEffect, useRef, useState } from "react";
import {
  api,
  firstPhrase,
  formatDate,
  useEvent,
  type DataPaths,
  type Hardware,
  type SetupStatus,
  type Settings,
  type Usage,
} from "../api";
import { Check, Download, External, Folder, Mic, Refresh, Stop } from "../icons";
import { toast } from "../toast";

const HF_MODEL_URL = "https://huggingface.co/pyannote/speaker-diarization-community-1";
const HF_TOKENS_URL = "https://huggingface.co/settings/tokens";

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
function HotkeyInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [capturing, setCapturing] = useState(false);
  const [preview, setPreview] = useState("");
  const [error, setError] = useState<string | null>(null);
  const single = !value.includes("+");
  return (
    <>
      <input
        readOnly
        className={capturing ? "capturing" : ""}
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

const LANGS: { code: string; label: string; native: string }[] = [
  { code: "en", label: "English", native: "English" },
  { code: "hi", label: "Hindi", native: "हिन्दी" },
  { code: "gu", label: "Gujarati", native: "ગુજરાતી" },
];

/** Which languages you speak, and how Hindi/Gujarati are written. */
function LanguagePicker({
  s,
  set,
}: {
  s: Settings;
  set: <K extends keyof Settings>(k: K, v: Settings[K]) => void;
}) {
  const chosen = s.languages.length ? s.languages : [s.language || "en"];
  const toggle = (code: string) => {
    const next = chosen.includes(code) ? chosen.filter((c) => c !== code) : [...chosen, code];
    if (next.length) set("languages", LANGS.map((l) => l.code).filter((c) => next.includes(c)));
  };
  const hi = chosen.includes("hi");
  const gu = chosen.includes("gu");
  return (
    <div className="field full">
      <span className="field-label">Languages you speak</span>
      <div className="row wrap">
        {LANGS.map((l) => (
          <button
            key={l.code}
            type="button"
            className={`lang-chip ${chosen.includes(l.code) ? "on" : ""}`}
            onClick={() => toggle(l.code)}
          >
            {chosen.includes(l.code) && <Check size={14} />} {l.native}
            {l.native !== l.label && <span className="small faint">{l.label}</span>}
          </button>
        ))}
      </div>
      <span className="field-hint">
        Each phrase is recognised in whichever of these you speak — mix them freely.
      </span>

      {hi && gu && (
        <div className="lang-sub">
          <span className="field-label">Hindi or Gujarati — which do you speak more?</span>
          <span className="field-hint">
            Written as spoken, Hindi and Gujarati are told apart by sound, and this one wins when it&apos;s unclear.
            Translated speech is always treated as this one.
          </span>
          <div className="segmented">
            {(["gu", "hi"] as const).map((code) => (
              <button
                key={code}
                type="button"
                className={s.prefer_indic === code ? "on" : ""}
                onClick={() => set("prefer_indic", code)}
              >
                {code === "gu" ? "ગુજરાતી Gujarati" : "हिन्दी Hindi"}
              </button>
            ))}
          </div>
        </div>
      )}

      {(hi || gu) && (
        <div className="lang-sub">
          <span className="field-label">How to write Hindi &amp; Gujarati</span>
          <select value={s.translate} onChange={(e) => set("translate", e.target.value as Settings["translate"])}>
            <option value="none">As spoken — in हिन्दी / ગુજરાતી script</option>
            {gu && <option value="gujarati">Translate Gujarati to English, keep Hindi</option>}
            <option value="all">Translate both to English</option>
          </select>
          <span className="field-hint">
            As spoken uses AI4Bharat IndicConformer, a model made for Indian languages (a 2.4 GB download on first use,
            with your Hugging Face token after accepting its terms on huggingface.co). Translating uses Whisper.
          </span>
        </div>
      )}
    </div>
  );
}

function Field({ label, hint, full, children }: { label: string; hint?: React.ReactNode; full?: boolean; children: React.ReactNode }) {
  return (
    <label className={`field ${full ? "full" : ""}`}>
      <span className="field-label">{label}</span>
      {children}
      {hint && <span className="field-hint">{hint}</span>}
    </label>
  );
}

/** Live RAM / GPU memory Voice Desk is using, refreshed every 2 s while visible. */
function MemoryNow() {
  const [u, setU] = useState<Usage | null>(null);
  useEffect(() => {
    let alive = true;
    const tick = () => api.resourceUsage().then((x) => alive && setU(x));
    tick();
    const t = setInterval(tick, 2000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);
  if (!u) return null;
  const gb = (n: number) => `${n < 0.1 ? n.toFixed(2) : n.toFixed(1)} GB`;
  return (
    <div className="full usage">
      <span className="field-label">In use right now</span>
      <div className="usage-row">
        <span>App {gb(u.app_gb)}</span>
        <span>Speech engine {u.speech_gb > 0.01 ? gb(u.speech_gb) : "asleep"}</span>
        <span>Task AI {u.task_ai_gb > 0.01 ? gb(u.task_ai_gb) : "not loaded"}</span>
        {u.gpu_used_gb != null && u.gpu_total_gb != null && (
          <span title="Windows doesn't report GPU memory per app, so this includes other apps">
            GPU memory {gb(u.gpu_used_gb)} of {gb(u.gpu_total_gb)}
          </span>
        )}
      </div>
    </div>
  );
}

function Toggle({ on, onChange, label, hint }: { on: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <div className="toggle-row full" onClick={() => onChange(!on)} role="switch" aria-checked={on}>
      <span className={`switch ${on ? "on" : ""}`} />
      <span>
        <span className="field-label">{label}</span>
        {hint && <span className="field-hint" style={{ display: "block" }}>{hint}</span>}
      </span>
    </div>
  );
}

function CheckItem({ ok, title, detail, children }: { ok: boolean; title: string; detail: React.ReactNode; children?: React.ReactNode }) {
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

const ENROLL_TEXT =
  "The quick brown fox jumps over the lazy dog. I'm teaching Voice Desk what my voice sounds like, " +
  "so that only I can give it commands. Tomorrow I will send the report, review the design, and call the team at three.";

function VoiceEnrollment({ onChange }: { onChange: () => void }) {
  const [profile, setProfile] = useState<{ exists: boolean; created_at: string | null }>({ exists: false, created_at: null });
  const [recording, setRecording] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [level, setLevel] = useState(0);
  const [busy, setBusy] = useState(false);
  const started = useRef(0);

  const refresh = () => api.voiceProfileInfo().then(setProfile);
  useEffect(() => {
    refresh();
    return () => {
      api.enrollStop(false).catch(() => {});
    };
  }, []);

  useEffect(() => {
    if (!recording) return;
    const t = setInterval(async () => {
      const s = (Date.now() - started.current) / 1000;
      setSeconds(s);
      setLevel((await api.audioLevels()).enroll ?? 0);
      if (s >= 25) finish();
    }, 100);
    return () => clearInterval(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [recording]);

  const start = async () => {
    try {
      await api.enrollStart();
      started.current = Date.now();
      setSeconds(0);
      setRecording(true);
    } catch (e) {
      toast(String(e));
    }
  };

  const finish = async () => {
    setRecording(false);
    setBusy(true);
    try {
      const r = await api.enrollStop(true);
      if (r) toast(`Voice saved (${r.seconds.toFixed(0)}s of speech). Commands now only work in your voice.`);
      refresh();
      onChange();
    } catch (e) {
      toast(String(e));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    await api.deleteVoiceProfile();
    refresh();
    onChange();
  };

  return (
    <div className="full">
      {recording ? (
        <>
          <p className="small muted" style={{ marginBottom: 8 }}>
            Read this aloud in your normal voice:
          </p>
          <div className="enroll-text">{ENROLL_TEXT}</div>
          <div className="row" style={{ marginTop: 12 }}>
            <div className="progress-track grow">
              <div className="progress-fill" style={{ width: `${Math.min(100, Math.sqrt(level) * 250)}%`, transition: "width 0.1s linear" }} />
            </div>
            <span className="small muted" style={{ minWidth: 40 }}>
              {seconds.toFixed(0)}s
            </span>
            <button className="primary" onClick={finish} disabled={seconds < 8}>
              <Stop size={12} /> {seconds < 8 ? "Keep reading…" : "Done"}
            </button>
          </div>
        </>
      ) : (
        <div className="row wrap">
          {profile.exists ? (
            <span className="badge ok">
              <Check size={12} /> Voice saved {profile.created_at ? formatDate(profile.created_at) : ""}
            </span>
          ) : (
            <span className="badge warn">Not trained yet</span>
          )}
          <span className="grow" />
          {profile.exists && (
            <button className="ghost danger" onClick={remove}>
              Forget my voice
            </button>
          )}
          <button className="primary" onClick={start} disabled={busy}>
            {busy ? <span className="spinner" /> : <Mic size={15} />} {profile.exists ? "Re-train" : "Train my voice"}
          </button>
        </div>
      )}
    </div>
  );
}

export default function SettingsView({ settings, onSaved }: { settings: Settings; onSaved: (s: Settings) => void }) {
  const [s, setS] = useState<Settings>(settings);
  const [setup, setSetup] = useState<SetupStatus | null>(null);
  const [paths, setPaths] = useState<DataPaths | null>(null);
  const [pull, setPull] = useState<{ status: string; pct: number } | null>(null);
  const dirty = JSON.stringify(s) !== JSON.stringify(settings);

  const refreshSetup = () => api.setupStatus().then(setSetup);
  useEffect(() => {
    refreshSetup();
    api.dataPaths().then(setPaths);
  }, []);
  useEvent("engine-status", refreshSetup);
  useEvent<{ status: string; pct: number }>("llm-pull", setPull);

  const [callApps, setCallApps] = useState("");
  const [hw, setHw] = useState<Hardware | null>(null);
  useEffect(() => {
    api.watchedCallApps().then(setCallApps);
    api.hardwareInfo().then(setHw);
  }, []);
  const set = <K extends keyof Settings>(k: K, v: Settings[K]) => setS((prev) => ({ ...prev, [k]: v }));

  const save = async () => {
    try {
      await api.saveSettings(s);
      onSaved(s);
      toast("Settings saved");
      refreshSetup();
    } catch (e) {
      toast(String(e));
    }
  };

  const downloadModel = async () => {
    setPull({ status: "starting", pct: -1 });
    try {
      await api.llmPull();
      toast("Task AI model downloaded");
    } catch (e) {
      toast(String(e));
    } finally {
      setPull(null);
      refreshSetup();
    }
  };

  const name = s.assistant_name || "Jarvis";
  const engine = setup?.engine;

  return (
    <section className="page">
      <header className="page-header">
        <h1>Settings</h1>
        <p>Everything runs on this computer. Nothing you say leaves it.</p>
      </header>

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
            <CheckItem
              ok={setup.engine_installed && engine?.state !== "error"}
              title="Speech engine"
              detail={
                !setup.engine_installed
                  ? "Not installed — run the setup script in the project folder."
                  : engine?.state === "ready"
                    ? `Ready: ${engine.model} on ${engine.device === "cuda" ? "GPU" : "CPU"}`
                    : engine?.state === "sleeping"
                      ? "Sleeping to save memory — wakes up when you start listening."
                      : engine?.state === "error"
                        ? engine.message
                        : "Loading…"
              }
            >
              {engine?.state === "error" && (
                <button onClick={() => api.engineRestart()}>
                  <Refresh size={14} /> Retry
                </button>
              )}
            </CheckItem>
            <CheckItem ok={setup.llm.model_ready} title="Task AI (Ollama + Qwen3)" detail={pull ? `${pull.status}…` : setup.llm.message}>
              {!setup.llm.installed ? (
                <button onClick={() => openUrl("https://ollama.com/download")}>
                  <External size={14} /> Get Ollama
                </button>
              ) : !setup.llm.model_ready && setup.llm.running ? (
                pull ? (
                  <div style={{ width: 160 }}>
                    <div className="progress-track">
                      <div className={`progress-fill ${pull.pct < 0 ? "indeterminate" : ""}`} style={{ width: `${Math.max(0, pull.pct)}%` }} />
                    </div>
                  </div>
                ) : (
                  <button className="primary" onClick={downloadModel}>
                    <Download size={14} /> Download
                  </button>
                )
              ) : null}
            </CheckItem>
            <CheckItem ok={setup.name_set} title="Your name" detail={setup.name_set ? `Tasks for “${settings.user_name}”` : "Needed to know which tasks are yours — set it below."} />
            <CheckItem
              ok={setup.voice_profile}
              title="Your voice"
              detail={setup.voice_profile ? "Only your voice can give commands." : "Optional: train it so nobody else can control Voice Desk."}
            />
            <CheckItem
              ok={setup.hf_token_set}
              title="Speaker detection"
              detail={setup.hf_token_set ? "Hugging Face token saved." : "Optional: tells meeting participants apart. Needs a free Hugging Face token."}
            />
          </div>
        )}
      </div>

      <div className="card">
        <div className="card-title">
          <h2>About you</h2>
        </div>
        <div className="settings-grid">
          <Field label="Your name" hint="How people say your name in meetings.">
            <input value={s.user_name} onChange={(e) => set("user_name", e.target.value)} placeholder="e.g. Nishchay" />
          </Field>
          <Field label="Other names people call you" hint="Nicknames or spellings, comma separated.">
            <input value={s.aliases} onChange={(e) => set("aliases", e.target.value)} />
          </Field>
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Assistant &amp; voice commands</h2>
        </div>
        <div className="settings-grid">
          <Field label="Assistant name" hint={`Say it before every command, e.g. “${name}, ${firstPhrase(s.cmd_pause)}”.`} full>
            <input value={s.assistant_name} onChange={(e) => set("assistant_name", e.target.value)} placeholder="Jarvis" />
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

      <div className="card">
        <div className="card-title">
          <h2>Your voice</h2>
        </div>
        <div className="settings-grid">
          <p className="small muted full">
            Read a short passage (about 15 seconds) so Voice Desk recognises you. Then commands spoken by other people — in the
            room or on a call — are ignored.
          </p>
          <VoiceEnrollment onChange={refreshSetup} />
          <Toggle
            on={s.voice_lock}
            onChange={(v) => set("voice_lock", v)}
            label="Only my voice can give commands"
            hint="Recommended. Needs a trained voice."
          />
          <Toggle
            on={s.only_my_voice}
            onChange={(v) => set("only_my_voice", v)}
            label="Only type what I say"
            hint="Ignore other voices near your microphone (open offices)."
          />
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Dictation</h2>
        </div>
        <div className="settings-grid">
          <Field label="Shortcut" hint="Click, then press 1–3 keys together (Esc to cancel).">
            <HotkeyInput value={s.dictation_hotkey} onChange={(v) => set("dictation_hotkey", v)} />
          </Field>
          <Field label="How the shortcut works">
            <select value={s.dictation_mode} onChange={(e) => set("dictation_mode", e.target.value as Settings["dictation_mode"])}>
              <option value="toggle">Single press — press to start, press to stop</option>
              <option value="double">Double press — press twice quickly to start / stop</option>
              <option value="long">Long press — hold to start / stop</option>
              <option value="hold">Push-to-talk — listen only while held</option>
            </select>
          </Field>
          {s.dictation_mode === "long" && (
            <Field label={`Hold for: ${s.long_press_s.toFixed(1)} seconds`} hint="How long to hold the shortcut before listening starts or stops.">
              <input type="range" min={0.5} max={5} step={0.5} value={s.long_press_s} onChange={(e) => set("long_press_s", Number(e.target.value))} />
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
            <input type="range" min={400} max={1500} step={50} value={s.silence_ms} onChange={(e) => set("silence_ms", Number(e.target.value))} />
          </Field>
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Speech recognition</h2>
        </div>
        <div className="settings-grid">
          <LanguagePicker s={s} set={set} />
          <Field
            label="Accuracy"
            hint="Auto: on a GPU, large-v3-turbo for English only; medium when Hindi/Gujarati are written as spoken (IndicConformer writes them, using less GPU memory); large-v3 when translating them."
          >
            <select value={s.whisper_model} onChange={(e) => set("whisper_model", e.target.value)}>
              <option value="auto">Auto (recommended)</option>
              <option value="large-v3">Best for translating Hindi &amp; Gujarati — large-v3 (GPU)</option>
              <option value="large-v3-turbo">Best for English — large-v3-turbo (GPU)</option>
              <option value="small">Balanced — small</option>
              <option value="base">Fastest — base</option>
            </select>
          </Field>
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
            <select value={s.whisper_device} onChange={(e) => set("whisper_device", e.target.value)}>
              <option value="auto">Auto — picks for this computer</option>
              {hw?.gpus.map((g) => (
                <option key={g.index} value={`cuda:${g.index}`}>
                  GPU: {g.name} ({g.total_gb.toFixed(0)} GB)
                </option>
              ))}
              {/* Older setting, or a GPU that's no longer connected. */}
              {s.whisper_device.startsWith("cuda") && !hw?.gpus.some((g) => `cuda:${g.index}` === s.whisper_device) && (
                <option value={s.whisper_device}>NVIDIA GPU</option>
              )}
              <option value="cpu">CPU only</option>
            </select>
          </Field>
          <Field label="Vocabulary" hint="Names and jargon to spell right, comma separated. Your name and the assistant name are included automatically.">
            <input value={s.vocabulary} onChange={(e) => set("vocabulary", e.target.value)} placeholder="Priya, Tauri, OKRs" />
          </Field>
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Speaker detection</h2>
        </div>
        <div className="settings-grid">
          <p className="small muted full">
            Tells meeting participants apart (Speaker 1, Speaker 2…). One-time setup: accept the model's terms, then create a
            token with <b>Read</b> access — that's all it needs.
          </p>
          <div className="row full">
            <button onClick={() => openUrl(HF_MODEL_URL)}>
              <External size={14} /> 1. Accept terms
            </button>
            <button onClick={() => openUrl(HF_TOKENS_URL)}>
              <External size={14} /> 2. Create a Read token
            </button>
          </div>
          <Field label="Hugging Face token" full>
            <input type="password" value={s.hf_token} onChange={(e) => set("hf_token", e.target.value)} placeholder="hf_…" />
          </Field>
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Task AI</h2>
        </div>
        <div className="settings-grid">
          <Field label="Ollama address">
            <input value={s.ollama_url} onChange={(e) => set("ollama_url", e.target.value)} />
          </Field>
          <Field label="Model">
            <input value={s.llm_model} onChange={(e) => set("llm_model", e.target.value)} />
          </Field>
          <div className="field full">
            <Toggle
              on={s.detect_meetings}
              onChange={(v) => set("detect_meetings", v)}
              label="Detect meetings"
              hint={`When a call starts, the floating bar offers to transcribe it; your shortcut starts it too (✕ means not this call). Watches ${callApps || "call apps"}. Windows only for now.`}
            />
          </div>
          <div className="field full">
            <span className="field-label">Opening a task's recording</span>
            <span className="field-hint">Click a task's source in My tasks to hear where it was said.</span>
            <div className="segmented">
              {[5, 0].map((n) => (
                <button
                  key={n}
                  type="button"
                  className={s.task_jump_lead_s === n ? "on" : ""}
                  onClick={() => set("task_jump_lead_s", n)}
                >
                  {n === 0 ? "Start right at the task" : `Start ${n} seconds before`}
                </button>
              ))}
            </div>
          </div>
        </div>
      </div>

      <div className="card">
        <div className="card-title">
          <h2>Storage &amp; memory</h2>
        </div>
        <div className="settings-grid">
          <Field label="Keep recordings for (days)" hint="Older recordings are deleted; their text stays. 0 = keep forever.">
            <input type="number" min={0} value={s.keep_audio_days} onChange={(e) => set("keep_audio_days", Math.max(0, Number(e.target.value)))} />
          </Field>
          <Field label="Free memory after idle (minutes)" hint="The speech engine shuts down when unused, and restarts when you talk. 0 = never.">
            <input type="number" min={0} value={s.unload_after_min} onChange={(e) => set("unload_after_min", Math.max(0, Number(e.target.value)))} />
          </Field>
          <MemoryNow />
          <Toggle
            on={s.close_to_tray}
            onChange={(v) => set("close_to_tray", v)}
            label="Keep running in the tray when the window is closed"
            hint="Off: closing Voice Desk also stops Ollama and the speech engine. On: the shortcut keeps working in the background."
          />
          {paths && (
            <div className="full">
              {(
                [
                  ["Your data", paths.app_data, "Database, recordings, voice profile"],
                  ["Recordings", paths.recordings, ""],
                  ["Speech models", paths.speech_models, ""],
                  ["Task AI models", paths.llm_models, ""],
                ] as const
              ).map(([label, p, hint]) => (
                <div key={label} className="path-row">
                  <span className="field-label" title={hint}>
                    {label}
                  </span>
                  <span className="path" title={p}>
                    {p}
                  </span>
                  <button className="ghost" onClick={() => api.openFolder(p).catch((e) => toast(String(e)))}>
                    <Folder size={15} /> Open
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="save-bar">
        <button className="primary" onClick={save} disabled={!dirty}>
          <Check size={15} /> Save settings
        </button>
        <span className="small muted">{dirty ? "You have unsaved changes." : "All changes saved."}</span>
      </div>
    </section>
  );
}
