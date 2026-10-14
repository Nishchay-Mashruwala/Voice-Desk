import { useEffect, useRef, useState } from "react";
import { api, useEvent, type InstallProgress, type LlmPull, type SetupChoices, type SetupPlan, type SetupStatus } from "../../api";
import { Download } from "../../icons";
import { gb, modelName } from "../../models";
import { toast } from "../../toast";
import { setupProgressText } from "../../wording";
import { ProgressBar } from "./common";

/** Progress events can come many times a second; the bar needs far fewer. */
const THROTTLE_MS = 250;

/** The task AI download's progress, in words. */
export function pullText(p: LlmPull): string {
  if (p.step === "runtime") return "Downloading the task AI runner";
  if (p.step === "model") return `Downloading ${modelName(p.model)}`;
  return "Ready";
}

/**
 * First run on a new computer: one download of what this computer needs, then
 * Voice Desk works offline. What's needed, how big it is and which packs are
 * offered come from the backend's plan; Download runs it all in the backend.
 *
 * A download keeps running when you leave Settings; coming back shows its
 * progress (from SetupStatus) instead of offering to start it again.
 */
export default function GettingReady({
  setup,
  plan,
  choices,
  onChoices,
  ensureSaved,
  onDone,
}: {
  setup: SetupStatus;
  plan: SetupPlan;
  choices: SetupChoices;
  onChoices: (c: SetupChoices) => void;
  /** Save unsaved settings first, so the download is for what's picked on screen. False: saving failed. */
  ensureSaved: () => Promise<boolean>;
  onDone: () => void;
}) {
  // Started from this visit (we're awaiting it), or already running in the background.
  const [started, setStarted] = useState(false);
  const running = started || setup.installing || setup.pulling;
  // Progress in words: the speech engine setup's ("engine-setup") or the task AI download's ("llm-pull").
  type Shown = { step: string; pct: number; detail: string };
  const words = (p: InstallProgress): Shown => ({ ...setupProgressText(p), pct: p.pct });
  const [progress, setProgress] = useState<Shown | null>(setup.install_progress && words(setup.install_progress));
  const [error, setError] = useState<string | null>(null);

  const lastShown = useRef(0);
  const show = (p: Shown) => {
    const now = Date.now();
    if (now - lastShown.current < THROTTLE_MS && p.pct < 100) return;
    lastShown.current = now;
    setProgress(p);
  };
  useEvent<InstallProgress>("engine-setup", (p) => show(words(p)));
  useEvent<LlmPull>("llm-pull", (p) => show({ step: pullText(p), pct: p.pct, detail: "" }));
  // Finished in the background (not awaited here): drop the old progress.
  useEffect(() => {
    if (!running) setProgress(null);
    else if (setup.installing && setup.install_progress) setProgress((p) => p ?? words(setup.install_progress!));
  }, [running, setup.installing, setup.install_progress]);

  const start = async () => {
    if (running) return;
    setError(null);
    setStarted(true);
    try {
      if (!(await ensureSaved())) return;
      await api.setupStart(choices);
      toast("Voice Desk is ready — it works offline from now on");
    } catch (e) {
      setError(String(e));
    } finally {
      setStarted(false);
      setProgress(null);
      onDone();
    }
  };

  const shown = progress ?? {
    step: setup.pulling ? "Downloading the task AI…" : "Setting up the speech engine…",
    pct: -1,
    detail: "",
  };
  const indicNote = (o: { extra_gb: number; model_gb: number }, lead: string) =>
    `${lead}${gb(o.extra_gb)}, then a ${gb(o.model_gb)} model when first used; needs your Hugging Face token`;

  return (
    <div className="getting-ready">
      <div className="field-label">Getting ready</div>
      <p className="small muted">
        One download of what this computer needs; after that Voice Desk works without the internet. If it's
        interrupted, it continues where it stopped.
      </p>
      <ul className="small getting-ready-list">
        {plan.steps.map((step) => (
          <li key={step.kind}>
            {step.kind === "engine_finish"
              ? "Speech engine — already on this computer; finishing its setup downloads only what's missing"
              : step.kind === "engine"
                ? `Speech engine and speech model — about ${gb(step.gb)}`
                : step.kind === "indic"
                  ? `Hindi/Gujarati written as spoken — about ${gb(step.gb)}, then its ${gb(step.later_gb ?? 0)} model when first used (needs your Hugging Face token)`
                  : `Task AI (${modelName(step.model ?? "")}) — about ${gb(step.gb)}`}
          </li>
        ))}
      </ul>
      {plan.offer_nvidia !== null && (
        <label className="row small">
          <input type="checkbox" checked={choices.nvidia} onChange={(e) => onChoices({ ...choices, nvidia: e.target.checked })} disabled={running} />
          Use the NVIDIA GPU for faster speech recognition (+{gb(plan.offer_nvidia)})
        </label>
      )}
      {plan.offer_indic && (
        <label className="row small">
          <input type="checkbox" checked={choices.indic} onChange={(e) => onChoices({ ...choices, indic: e.target.checked })} disabled={running} />
          Hindi/Gujarati written as spoken ({indicNote(plan.offer_indic, "+")})
        </label>
      )}
      {running ? (
        <div className="getting-ready-progress" aria-live="polite">
          <div className="row small">
            <span className="spinner dark" /> {shown.step}
            {shown.pct >= 0 && <span className="faint"> · {Math.round(shown.pct)}%</span>}
            {shown.detail && <span className="faint"> · {shown.detail}</span>}
          </div>
          <ProgressBar pct={shown.pct} />
        </div>
      ) : (
        <div className="row">
          <button className="primary" onClick={start}>
            <Download size={14} /> {error ? "Try again" : plan.total_gb > 0 ? `Download (about ${gb(plan.total_gb)})` : "Finish setup"}
          </button>
          {error && <span className="small bad">{error}</span>}
        </div>
      )}
    </div>
  );
}
