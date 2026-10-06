import { useEffect, useRef, useState } from "react";
import { api, useEvent, type Hardware, type InstallProgress, type SetupStatus } from "../../api";
import { Download } from "../../icons";
import { ENGINE_DOWNLOAD, gb, INDIC_MODEL_GB, TASK_RUNTIME_GB, type ModelSpec } from "../../models";
import { toast } from "../../toast";
import { ProgressBar } from "./common";

/** Progress events can come many times a second; the bar needs far fewer. */
const THROTTLE_MS = 250;

/**
 * First run on a new computer: one download of what this computer needs, then
 * Voice Desk works offline. Optional packs are offered only where they help.
 * The single Download control for the speech engine and the task AI.
 *
 * A download keeps running when you leave Settings; coming back shows its
 * progress (from SetupStatus) instead of offering to start it again.
 */
export default function GettingReady({
  hw,
  setup,
  indicChosen,
  needEngine,
  needIndic,
  needTaskAi,
  taskModelReady,
  task,
  ensureSaved,
  onDone,
}: {
  hw: Hardware | null;
  setup: SetupStatus;
  indicChosen: boolean;
  needEngine: boolean;
  /** Hindi/Gujarati were chosen after the engine was set up without them. */
  needIndic: boolean;
  needTaskAi: boolean;
  /** The task model is already downloaded (only its runner is missing). */
  taskModelReady: boolean;
  /** The task model that would be downloaded (the one picked in Settings). */
  task: ModelSpec;
  /** Save unsaved settings first, so the download is for what's picked on screen. False: saving failed. */
  ensureSaved: () => Promise<boolean>;
  onDone: () => void;
}) {
  const bigGpu = (hw?.gpus ?? []).some((g) => g.total_gb >= 3);
  const [nvidia, setNvidia] = useState(bigGpu);
  const [indic, setIndic] = useState(indicChosen);
  useEffect(() => setNvidia(bigGpu), [bigGpu]);

  // Started from this visit (we're awaiting it), or already running in the background.
  const [started, setStarted] = useState(false);
  const running = started || setup.installing || setup.pulling;
  const [progress, setProgress] = useState<InstallProgress | null>(setup.install_progress);
  const [error, setError] = useState<string | null>(null);

  const lastShown = useRef(0);
  const show = (p: InstallProgress) => {
    const now = Date.now();
    if (now - lastShown.current < THROTTLE_MS && p.pct < 100) return;
    lastShown.current = now;
    setProgress(p);
  };
  useEvent<InstallProgress>("engine-setup", show);
  useEvent<{ status: string; pct: number }>("llm-pull", (p) => show({ step: p.status, pct: p.pct, detail: "" }));
  // Finished in the background (not awaited here): drop the old progress.
  useEffect(() => {
    if (!running) setProgress(null);
    else if (setup.installing && setup.install_progress) setProgress((p) => p ?? setup.install_progress);
  }, [running, setup.installing, setup.install_progress]);

  // The engine is already on this computer, its setup just didn't finish:
  // finishing it fetches only what's missing, so it isn't offered as a download.
  const finishEngine = needEngine && setup.engine_partial;
  const engineGb = ENGINE_DOWNLOAD.base + (nvidia ? ENGINE_DOWNLOAD.nvidia : ENGINE_DOWNLOAD.cpu);
  // Only the parts not downloaded yet.
  const taskGb = (taskModelReady ? 0 : task.downloadGb) + (setup.llm.installed ? 0 : TASK_RUNTIME_GB);
  const total =
    (needEngine && !finishEngine ? engineGb + (indic && indicChosen ? ENGINE_DOWNLOAD.indic : 0) : 0) +
    (needIndic ? ENGINE_DOWNLOAD.indic : 0) +
    (needTaskAi ? taskGb : 0);

  const start = async () => {
    if (running) return;
    setError(null);
    setStarted(true);
    try {
      if (!(await ensureSaved())) return;
      // Saving may have changed what's needed (e.g. a different task model): ask again.
      const now = await api.setupStatus();
      const wantIndic = indicChosen && !!now.engine_packs && !now.engine_packs.indic;
      // Finishing keeps the packs already on disk (and adds Hindi/Gujarati if chosen).
      if (!now.engine_installed && now.engine_partial) await api.engineInstall({ nvidia: false, indic: indicChosen });
      else if (!now.engine_installed) await api.engineInstall({ nvidia: nvidia && bigGpu, indic: indic && indicChosen });
      else if (wantIndic) await api.engineInstall({ nvidia: false, indic: true }); // keeps packs already installed
      if (!(now.llm.installed && now.llm.model_ready)) await api.llmPull();
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

  return (
    <div className="getting-ready">
      <div className="field-label">Getting ready</div>
      <p className="small muted">
        One download of what this computer needs; after that Voice Desk works without the internet. If it's
        interrupted, it continues where it stopped.
      </p>
      <ul className="small getting-ready-list">
        {finishEngine ? (
          <li>Speech engine — already on this computer; finishing its setup downloads only what's missing</li>
        ) : (
          needEngine && <li>Speech engine and speech model — about {gb(engineGb)}</li>
        )}
        {needIndic && (
          <li>
            Hindi/Gujarati written as spoken — about {gb(ENGINE_DOWNLOAD.indic)}, then its {gb(INDIC_MODEL_GB)} model when first
            used (needs your Hugging Face token)
          </li>
        )}
        {needTaskAi && (
          <li>
            Task AI ({task.name}) — about {gb(taskGb)}
          </li>
        )}
      </ul>
      {needEngine && !finishEngine && bigGpu && (
        <label className="row small">
          <input type="checkbox" checked={nvidia} onChange={(e) => setNvidia(e.target.checked)} disabled={running} />
          Use the NVIDIA GPU for faster speech recognition (+{gb(ENGINE_DOWNLOAD.nvidia - ENGINE_DOWNLOAD.cpu)})
        </label>
      )}
      {needEngine && !finishEngine && indicChosen && (
        <label className="row small">
          <input type="checkbox" checked={indic} onChange={(e) => setIndic(e.target.checked)} disabled={running} />
          Hindi/Gujarati written as spoken (+{gb(ENGINE_DOWNLOAD.indic)}, then a {gb(INDIC_MODEL_GB)} model when first used;
          needs your Hugging Face token)
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
            <Download size={14} /> {error ? "Try again" : total > 0 ? `Download (about ${gb(total)})` : "Finish setup"}
          </button>
          {error && <span className="small bad">{error}</span>}
        </div>
      )}
    </div>
  );
}
