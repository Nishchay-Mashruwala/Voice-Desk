/**
 * Words for what the backend reports as data: progress steps, notices,
 * downloads and models. The backend sends ids and numbers; this is where they
 * become sentences.
 */
import type { CallApps, EngineStatus, InstallProgress, ModelInfo, SessionNotice } from "./api";
import { gb, modelName } from "./models";

/** A model being downloaded, by the id the engine sends ("whisper:medium", "indic"…). */
export function downloadModelName(model: string): string {
  if (model.startsWith("whisper:")) return `Speech model ${model.slice("whisper:".length)}`;
  const names: Record<string, string> = {
    indic: "Hindi/Gujarati model (IndicConformer)",
    voice_id: "Voice ID model",
    speakers: "Speaker detection model",
  };
  return names[model] ?? "a model";
}

/** "Downloading Speech model medium… 42%" (or "… 310 MB" while the size isn't known). */
export function downloadingText(model: string, doneMb: number, totalMb: number | null | undefined): string {
  const amount = totalMb ? `${Math.round((doneMb / totalMb) * 100)}%` : `${Math.round(doneMb)} MB`;
  return `Downloading ${downloadModelName(model)}… ${amount}`;
}

/** The engine's state while downloading a model, in words (empty otherwise). */
export function engineDownloadText(e: EngineStatus): string {
  return e.state === "downloading" && e.model ? downloadingText(e.model, e.done_mb ?? 0, e.total_mb) : "";
}

/** A downloaded model in the Storage list. */
export function modelInfoName(m: ModelInfo): string {
  switch (m.kind) {
    case "speech":
      return `Speech model: Whisper ${m.model ?? ""}`;
    case "task_ai":
      return `Task AI: ${modelName(m.model ?? "")}`;
    case "voice_id":
      return "Voice ID";
    case "speakers":
      return "Speaker detection";
    case "indic":
      return "Hindi/Gujarati model";
    case "indic_support":
      return "Hindi/Gujarati model (support files)";
    case "old_speakers":
      return "Old speaker detection (no longer used)";
    default:
      return `Other: ${m.model ?? ""}`;
  }
}

const MEETING_STAGES: Record<string, string> = {
  loading_model: "Loading speech model",
  checking_audio: "Checking audio",
  transcribing_mic: "Transcribing your microphone",
  identifying_speakers: "Identifying speakers",
  transcribing: "Transcribing",
  transcribing_system: "Transcribing meeting audio",
  transcript_ready: "Transcript ready",
  finding_tasks: "Finding your tasks",
  done: "Done",
};

/** Where a meeting's processing is ("meeting-progress" stage). */
export const meetingStage = (stage: string) => MEETING_STAGES[stage] ?? stage;

const SETUP_STEPS: Record<string, string> = {
  engine: "Installing the speech engine",
  nvidia: "Adding NVIDIA speed-up",
  indic: "Adding Hindi/Gujarati",
  models: "Downloading speech models",
  done: "Ready",
};

/** The speech engine setup's step and detail ("engine-setup" event), in words. */
export function setupProgressText(p: InstallProgress): { step: string; detail: string } {
  const step = p.step === "python" ? (p.pct < 10 ? "Downloading Python" : "Unpacking Python") : (SETUP_STEPS[p.step] ?? p.step);
  const d = p.detail;
  let detail = "";
  if (d?.package) detail = `Downloading ${d.package}…`;
  else if (d?.installing) detail = "Installing packages…";
  else if (d?.model !== undefined) detail = d.pct !== undefined ? `Downloading ${downloadModelName(d.model)}… ${d.pct}%` : `Downloading ${downloadModelName(d.model)}… ${d.mb ?? 0} MB`;
  else if (d?.text) detail = d.text;
  return { step, detail };
}

/** A notice from the backend ("session-notice"), in full; `name` is the assistant name. */
export function noticeText(n: SessionNotice, name: string): string {
  switch (n.kind) {
    case "meeting_recording":
      return n.warning ?? (n.app ? `Recording the ${n.app} call` : "Recording a meeting");
    case "press_again_to_stop":
      return "Press the shortcut again to stop the meeting recording";
    case "meeting_stopped":
      return n.reason === "quiet"
        ? `Nobody has spoken for ${n.quiet_min ?? 3} minutes, so the meeting recording stopped. Finding tasks…`
        : "The call ended, so the meeting recording stopped. Finding tasks…";
    case "typing_paused":
      return "Typing paused";
    case "typing_resumes_after_tasks":
      return "Typing will resume after task recording";
    case "command_not_your_voice":
      return `Ignored a “${name}” command: it didn't sound like your voice`;
    case "nothing_to_copy":
      return "Nothing dictated yet";
    case "copied_last":
      return "Last dictation copied";
    default:
      return n.message ?? "";
  }
}

/** A version of a notice that fits the floating bar. */
export function noticeShort(n: SessionNotice, name: string): string {
  switch (n.kind) {
    case "meeting_recording":
      return "● Recording";
    case "press_again_to_stop":
      return "Press again to stop";
    case "meeting_stopped":
      return "✓ Meeting saved";
    default:
      return noticeText(n, name);
  }
}

/** The call apps watched on this computer, as a phrase. */
export function callAppsText(c: CallApps): string {
  const apps = [...c.apps, ...(c.browsers ? ["browsers (Google Meet and other web calls)"] : [])];
  const list = apps.length > 1 ? `${apps.slice(0, -1).join(", ")}, and ${apps[apps.length - 1]}` : apps.join("");
  return list + (c.needs_pactl ? ". Needs pactl (PipeWire or PulseAudio)" : "");
}

/** A size note for a task model: "Qwen3 4B (2.5 GB)". */
export const taskModelLabel = (model: string, sizeGb: number) => `${modelName(model)} (${gb(sizeGb)})`;
