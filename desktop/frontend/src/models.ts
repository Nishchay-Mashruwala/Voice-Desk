/**
 * How models and sizes are shown. Which models exist, what they need, and
 * which ones this computer can run come from the backend (`api.modelOptions`).
 */

/** A size in GB as people read it: "310 MB", "1.6 GB". The one size format used everywhere. */
export const gb = (n: number) => (n < 1 ? `${Math.round(n * 1000)} MB` : `${n.toFixed(1)} GB`);

/** Each model's name and what it's for, by model id. */
const MODEL_TEXT: Record<string, { name: string; purpose: string }> = {
  "large-v3-turbo": { name: "large-v3-turbo", purpose: "Best for English" },
  medium: { name: "medium", purpose: "English with Hindi/Gujarati" },
  "large-v3": { name: "large-v3", purpose: "Best for translating Hindi/Gujarati" },
  small: { name: "small", purpose: "Balanced" },
  base: { name: "base", purpose: "Fastest, least accurate" },
  "qwen3-4b": { name: "Qwen3 4B", purpose: "Finds tasks reliably" },
  "qwen3-1.7b": { name: "Qwen3 1.7B", purpose: "Lighter, misses more tasks" },
};

export const modelName = (id: string) => MODEL_TEXT[id]?.name ?? id;
export const modelPurpose = (id: string) => MODEL_TEXT[id]?.purpose ?? "";
