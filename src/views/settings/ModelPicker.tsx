import type { Hardware } from "../../api";
import { fitModel, gb, whyNot, type Fit, type ModelSpec } from "../../models";

/**
 * Choose a model among the ones this computer can run, each with its download
 * size and what it uses here. Models it can't run aren't offered (one line says why).
 */
export default function ModelPicker({
  label,
  hint,
  models,
  value,
  autoNote,
  hw,
  device,
  nvidiaReady,
  downloaded,
  onChange,
}: {
  label: string;
  hint: string;
  models: ModelSpec[];
  value: string;
  /** What Auto uses now, e.g. "large-v3-turbo on the GPU". */
  autoNote: string;
  hw: Hardware;
  device: string;
  nvidiaReady: boolean;
  /** Ids of the models on disk (Settings → Downloaded models). */
  downloaded: string[];
  onChange: (id: string) => void;
}) {
  const fits = models.map((m) => fitModel(m, hw, device, nvidiaReady)).filter((f): f is Fit => f !== null);
  const hidden = models.filter((m) => !fits.some((f) => f.spec.id === m.id));
  // A saved choice this computer can't run is treated as Auto (as the engine does).
  const current = fits.some((f) => f.spec.id === value) ? value : "auto";
  return (
    <div className="field full">
      <span className="field-label">{label}</span>
      <div className="model-options" role="radiogroup" aria-label={label}>
        <button
          type="button"
          role="radio"
          aria-checked={current === "auto"}
          className={`model-option ${current === "auto" ? "on" : ""}`}
          onClick={() => onChange("auto")}
        >
          <span className="model-option-title">
            Auto <span className="faint">— picks for this computer</span>
          </span>
          {autoNote && <span className="model-option-specs">Now: {autoNote}</span>}
        </button>
        {fits.map(({ spec, on, use }) => (
          <button
            key={spec.id}
            type="button"
            role="radio"
            aria-checked={current === spec.id}
            className={`model-option ${current === spec.id ? "on" : ""}`}
            onClick={() => onChange(spec.id)}
          >
            <span className="model-option-title">
              {spec.name} <span className="faint">— {spec.purpose}</span>
              {downloaded.some((d) => d.endsWith(spec.file)) ? (
                <span className="badge ok">Downloaded</span>
              ) : (
                <span className="badge">Downloads {gb(spec.downloadGb)}</span>
              )}
            </span>
            <span className="model-option-specs">
              <span>{on === "gpu" ? "On the GPU" : "On the CPU"}</span>
              <span>RAM {gb(use.ramGb)}</span>
              {on === "gpu" && <span>GPU {gb(use.gpuGb)}</span>}
              <span>
                CPU ~{Math.round(use.cores)} {use.cores < 1.5 ? "core" : "cores"}
              </span>
              <span>{use.speed}</span>
            </span>
          </button>
        ))}
      </div>
      {hidden.length > 0 && (
        <span className="field-hint">
          Not offered on this computer: {hidden.map((m) => `${m.name} (${whyNot(m, nvidiaReady)})`).join(", ")}.
        </span>
      )}
      <span className="field-hint">{hint}</span>
    </div>
  );
}
