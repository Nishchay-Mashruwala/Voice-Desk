import type { ModelOption, NotOffered } from "../../api";
import { gb, modelName, modelPurpose } from "../../models";

/** Why a model isn't offered, in a few words. */
function whyNot(n: NotOffered | null): string {
  if (!n) return "";
  if (n.needs === "gpu") return `needs an NVIDIA GPU with ${gb(n.gb)}`;
  if (n.needs === "nvidia_pack") return "needs the NVIDIA speed-up";
  return `needs ${n.gb} GB of RAM`;
}

/**
 * Choose a model among the ones this computer can run (as the backend says),
 * each with its download size and what it uses here. Models it can't run
 * aren't offered (one line says why), unless one is the current choice.
 */
export default function ModelPicker({
  label,
  hint,
  options,
  selected,
  autoNote,
  per,
  onChange,
}: {
  label: string;
  hint: string;
  options: ModelOption[];
  /** What's chosen: a model id, or "auto". */
  selected: string;
  /** What Auto uses now, e.g. "large-v3-turbo on the GPU". */
  autoNote: string;
  /** What the speed is measured on. */
  per: "minute of speech" | "meeting";
  onChange: (id: string) => void;
}) {
  const shown = options.filter((m) => m.fit || m.id === selected);
  const hidden = options.filter((m) => !shown.includes(m));
  return (
    <div className="field full">
      <span className="field-label">{label}</span>
      <div className="model-options" role="radiogroup" aria-label={label}>
        <button
          type="button"
          role="radio"
          aria-checked={selected === "auto"}
          className={`model-option ${selected === "auto" ? "on" : ""}`}
          onClick={() => onChange("auto")}
        >
          <span className="model-option-title">
            Auto <span className="faint">— picks for this computer</span>
          </span>
          {autoNote && <span className="model-option-specs">Now: {autoNote}</span>}
        </button>
        {shown.map((m) => (
          <button
            key={m.id}
            type="button"
            role="radio"
            aria-checked={selected === m.id}
            className={`model-option ${selected === m.id ? "on" : ""}`}
            onClick={() => onChange(m.id)}
          >
            <span className="model-option-title">
              {modelName(m.id)} <span className="faint">— {modelPurpose(m.id)}</span>
              {m.downloaded ? <span className="badge ok">Downloaded</span> : <span className="badge">Downloads {gb(m.download_gb)}</span>}
            </span>
            {m.fit ? (
              <span className="model-option-specs">
                <span>{m.fit.on === "gpu" ? "On the GPU" : "On the CPU"}</span>
                <span>RAM {gb(m.fit.ram_gb)}</span>
                {m.fit.on === "gpu" && <span>GPU {gb(m.fit.gpu_gb)}</span>}
                <span>
                  CPU ~{Math.round(m.fit.cores)} {m.fit.cores < 1.5 ? "core" : "cores"}
                </span>
                <span>
                  ~{m.fit.speed_s} s per {per}
                </span>
              </span>
            ) : (
              <span className="model-option-specs">Not suited to this computer: {whyNot(m.not_offered)}</span>
            )}
          </button>
        ))}
      </div>
      {hidden.length > 0 && (
        <span className="field-hint">
          Not offered on this computer: {hidden.map((m) => `${modelName(m.id)} (${whyNot(m.not_offered)})`).join(", ")}.
        </span>
      )}
      <span className="field-hint">{hint}</span>
    </div>
  );
}
