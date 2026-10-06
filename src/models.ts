import type { Hardware } from "./api";

/**
 * The speech and task models Settings offers, with what each needs and uses.
 * Settings shows only the ones this computer can run.
 *
 * Measured 2026-10-05 on a Ryzen 7 5800H with an RTX 3050 Laptop 4 GB: speech
 * on 36 s of speech, the task AI on one meeting-sized request (~3 KB of
 * transcript). RAM is the peak, loading included.
 */
export interface Use {
  ramGb: number;
  /** GPU memory; 0 on the CPU. */
  gpuGb: number;
  /** Busy CPU cores while working. */
  cores: number;
  speed: string;
}

export interface ModelSpec {
  id: string;
  name: string;
  purpose: string;
  downloadGb: number;
  /** On an NVIDIA GPU. Missing: not offered there. */
  gpu?: Use;
  /** On the CPU. Missing: too slow there. Computers with less RAM than `minRamGb` don't get it. */
  cpu?: Use & { minRamGb: number };
  /** Whisper on the CPU keeps to the threads Voice Desk allows (half the cores);
   * llama-server measured ~8 cores with `-t 4`, so its figure isn't capped. */
  capped: boolean;
  /** How a downloaded copy is named (Settings → Storage ids), to show "Downloaded". */
  file: string;
}

/** GPU memory left free for the task AI and other apps (as the engine's GPU_SPARE_GB). */
const GPU_SPARE_GB = 0.3;

export const SPEECH_MODELS: ModelSpec[] = [
  {
    id: "large-v3-turbo",
    name: "large-v3-turbo",
    purpose: "Best for English",
    downloadGb: 1.6,
    gpu: { ramGb: 1.7, gpuGb: 1.3, cores: 1, speed: "~10 s per minute of speech" },
    capped: true,
    file: "faster-whisper-large-v3-turbo",
  },
  {
    id: "medium",
    name: "medium",
    purpose: "English with Hindi/Gujarati",
    downloadGb: 1.5,
    gpu: { ramGb: 1.6, gpuGb: 1.2, cores: 1, speed: "~15 s per minute of speech" },
    capped: true,
    file: "faster-whisper-medium",
  },
  {
    id: "large-v3",
    name: "large-v3",
    purpose: "Best for translating Hindi/Gujarati",
    downloadGb: 2.9,
    gpu: { ramGb: 3.2, gpuGb: 2.3, cores: 1, speed: "~29 s per minute of speech" },
    capped: true,
    file: "faster-whisper-large-v3",
  },
  {
    id: "small",
    name: "small",
    purpose: "Balanced",
    downloadGb: 0.46,
    gpu: { ramGb: 0.7, gpuGb: 0.5, cores: 1, speed: "~7 s per minute of speech" },
    cpu: { ramGb: 0.7, gpuGb: 0, cores: 4, speed: "~19 s per minute of speech", minRamGb: 6 },
    capped: true,
    file: "faster-whisper-small",
  },
  {
    id: "base",
    name: "base",
    purpose: "Fastest, least accurate",
    downloadGb: 0.14,
    cpu: { ramGb: 0.3, gpuGb: 0, cores: 3.5, speed: "~7 s per minute of speech", minRamGb: 0 },
    capped: true,
    file: "faster-whisper-base",
  },
];

export const TASK_MODELS: ModelSpec[] = [
  {
    id: "qwen3-4b",
    name: "Qwen3 4B",
    purpose: "Finds tasks reliably",
    downloadGb: 2.5,
    gpu: { ramGb: 2.6, gpuGb: 2.7, cores: 1, speed: "~26 s per meeting" },
    cpu: { ramGb: 3.7, gpuGb: 0, cores: 8, speed: "~48 s per meeting", minRamGb: 6 },
    capped: false,
    file: "Qwen3-4B-Q4_K_M.gguf",
  },
  {
    id: "qwen3-1.7b",
    name: "Qwen3 1.7B",
    purpose: "Lighter, misses more tasks",
    downloadGb: 1.1,
    gpu: { ramGb: 1.3, gpuGb: 1.3, cores: 1, speed: "~16 s per meeting" },
    cpu: { ramGb: 2.1, gpuGb: 0, cores: 8, speed: "~21 s per meeting", minRamGb: 0 },
    capped: false,
    file: "Qwen3-1.7B-Q4_K_M.gguf",
  },
];

export interface Fit {
  spec: ModelSpec;
  on: "gpu" | "cpu";
  use: Use;
}

/**
 * Where a model would run on this computer, or null if it can't run well.
 * `nvidiaReady`: Whisper can use an NVIDIA GPU only with the NVIDIA pack (the
 * task AI uses the GPU through Vulkan and needs no pack).
 */
export function fitModel(spec: ModelSpec, hw: Hardware, device: string, nvidiaReady: boolean): Fit | null {
  const gpuGb = Math.max(
    0,
    ...hw.gpus.filter((g) => device === "auto" || device === "cuda" || device === `cuda:${g.index}`).map((g) => g.total_gb),
  );
  if (spec.gpu && device !== "cpu" && nvidiaReady && gpuGb >= spec.gpu.gpuGb + GPU_SPARE_GB) {
    return { spec, on: "gpu", use: spec.gpu };
  }
  if (spec.cpu && hw.ram_total_gb >= spec.cpu.minRamGb) {
    const cores = Math.min(spec.cpu.cores, spec.capped ? hw.threads : hw.cores);
    return { spec, on: "cpu", use: { ...spec.cpu, cores } };
  }
  return null;
}

/** Why a model isn't offered on this computer, in a few words. */
export function whyNot(spec: ModelSpec, nvidiaReady: boolean): string {
  if (!spec.cpu && spec.gpu) {
    return nvidiaReady ? `needs an NVIDIA GPU with ${gb(spec.gpu.gpuGb + GPU_SPARE_GB)}` : "needs the NVIDIA speed-up";
  }
  return `needs ${spec.cpu?.minRamGb ?? 0} GB of RAM`;
}

/** A size in GB as people read it: "310 MB", "1.6 GB". The one size format used everywhere. */
export const gb = (n: number) => (n < 1 ? `${Math.round(n * 1000)} MB` : `${n.toFixed(1)} GB`);

/**
 * What first-run setup downloads (GB), as the engine installer fetches it:
 * the speech engine itself, then either the NVIDIA (CUDA) or the CPU runtime
 * with a starter speech model, and the Hindi/Gujarati pack (what shrinks its
 * model to int8; no PyTorch).
 */
export const ENGINE_DOWNLOAD = { base: 0.4, nvidia: 3.3, cpu: 0.5, indic: 0.03 };
/** The Hindi/Gujarati model (IndicConformer), downloaded when first used and then
 * kept as a 1.0 GB int8 copy. */
export const INDIC_MODEL_GB = 2.4;
/** The task AI's runtime (llama-server), downloaded with its first model. */
export const TASK_RUNTIME_GB = 0.03;

/**
 * The task model a choice means here: the chosen one if this computer can run
 * it, else what Auto picks (the first that fits, as the backend does), else
 * the one the backend reports using (its label, e.g. "Qwen3 4B (2.5 GB)").
 */
export function taskSpec(choice: string, backendLabel: string, hw: Hardware | null, device: string): ModelSpec {
  const fits = (m: ModelSpec) => !hw || fitModel(m, hw, device, true) !== null;
  return (
    TASK_MODELS.find((m) => m.id === choice && fits(m)) ??
    (hw ? TASK_MODELS.find(fits) : undefined) ??
    TASK_MODELS.find((m) => backendLabel.startsWith(m.name)) ??
    TASK_MODELS[0]
  );
}
