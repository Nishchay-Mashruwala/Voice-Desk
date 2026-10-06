import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import { useEffect, useRef } from "react";

export interface Settings {
  user_name: string;
  aliases: string;
  dictation_hotkey: string;
  dictation_mode: "toggle" | "double" | "long" | "hold";
  long_press_s: number;
  /** What the keyboard shortcut starts: listening (typing) or a meeting recording. */
  shortcut_starts: "listen" | "meeting";
  insert_method: "paste" | "type";
  silence_ms: number;
  assistant_name: string;
  cmd_stop: string;
  cmd_pause: string;
  cmd_resume: string;
  cmd_record_tasks: string;
  cmd_tasks_recorded: string;
  voice_lock: boolean;
  only_my_voice: boolean;
  language: string;
  languages: string[];
  prefer_indic: "hi" | "gu";
  translate: "none" | "gujarati" | "all";
  whisper_model: string;
  /** "auto" | "cuda" (first NVIDIA GPU) | "cuda:N" (that GPU) | "cpu". Applies to speech and the task AI. */
  device: string;
  vocabulary: string;
  /** Words and phrases left out of every transcript ("umm, uh, the the"). */
  omit_words: string;
  unload_after_min: number;
  keep_audio_days: number;
  close_to_tray: boolean;
  detect_meetings: boolean;
  auto_stop_meetings: boolean;
  task_jump_lead_s: number;
  hf_token: string;
  /** "auto" | "qwen3-1.7b" | "qwen3-4b" */
  llm_model: string;
}

/** A word in a recording, with its time (s) and what happened to it. */
export interface Word {
  w: string;
  s: number;
  e: number;
  st?: string;
}

export interface Dictation {
  id: number;
  text: string;
  duration_ms: number;
  created_at: string;
  has_audio: boolean;
  words: Word[] | null;
  meeting_id: number | null;
  /** Tasks found in this recording ("Find tasks"), underlined where they were said. */
  tasks: { description: string; quote: string | null }[];
}

export type MeetingStatus = "recording" | "transcribing" | "extracting" | "done" | "error";

export interface Meeting {
  id: number;
  title: string;
  kind: "meeting" | "capture" | "dictation";
  started_at: string;
  ended_at: string | null;
  status: MeetingStatus;
  error: string | null;
  duration_s: number | null;
  summary: string | null;
  task_count: number;
}

export interface Segment {
  start: number;
  end: number;
  speaker: string;
  text: string;
  /** Word timings; missing in older transcripts. */
  words?: Word[];
}

export interface Task {
  id: number;
  meeting_id: number | null;
  meeting_title: string | null;
  meeting_kind: Meeting["kind"] | null;
  /** The Listen recording it was said in (voice task recordings and "Find tasks"). */
  dictation_id: number | null;
  description: string;
  assigned_by: string | null;
  due: string | null;
  quote: string | null;
  done: boolean;
  position: number;
  created_at: string;
}

/**
 * Open a recording on its page: a meeting (Meetings) or a Listen recording.
 * With `play`, playback starts `leadS` seconds before `quote` was said.
 */
export interface SourceFocus {
  meetingId?: number;
  dictationId?: number;
  quote: string | null;
  /** Exact time to play from (search results), instead of finding `quote`. */
  atS?: number | null;
  leadS: number;
  play: boolean;
  /** Changes on every click, so clicking the same task again replays it. */
  nonce: number;
}

export interface Hardware {
  gpus: { index: number; name: string; total_gb: number; free_gb: number }[];
  ram_total_gb: number;
  ram_free_gb: number;
  cores: number;
  threads: number;
}

export interface Usage {
  app_gb: number;
  speech_gb: number;
  task_ai_gb: number;
  gpu_used_gb: number | null;
  gpu_total_gb: number | null;
}

/** Disk space Voice Desk takes, in GB. */
export interface DiskUsage {
  app_gb: number;
  /** The speech engine's Python and packages, and the task AI's runner. */
  engines_gb: number;
  models_gb: number;
  /** Database, recordings, voice profile. */
  data_gb: number;
}

export interface SearchHit {
  kind: "recording" | "meeting" | "task";
  title: string;
  snippet: string;
  match_start: number;
  match_end: number;
  created_at: string;
  meeting_id: number | null;
  dictation_id: number | null;
  at_s: number | null;
}

export interface ModelInfo {
  id: string;
  name: string;
  size_gb: number;
  in_use: boolean;
}

export interface Levels {
  listening: number | null;
  mic: number | null;
  system: number | null;
  enroll: number | null;
}

export type SessionState = "idle" | "starting" | "listening" | "paused" | "stopping";

export interface SessionStatus {
  state: SessionState;
  capturing: boolean;
  processing: number;
  assistant_name: string;
  /** Seconds since listening started. */
  listening_s: number | null;
  /** A meeting being recorded. */
  meeting: { id: number; elapsed_s: number } | null;
  /** A call is on and the overlay offers to transcribe it ("Zoom"). */
  call_prompt: string | null;
  /** Listening during that call: seconds until it becomes a meeting recording. */
  call_switch_s: number | null;
}

export interface HeardPart {
  type: "text" | "command";
  text?: string;
  command?: string;
  status: string;
}

export interface EngineStatus {
  /** "downloading": fetching a model first (`message` says which). */
  state: "loading" | "downloading" | "ready" | "sleeping" | "error";
  device?: string;
  model?: string;
  message?: string;
}

export interface MeetingProgress {
  id: number;
  stage: string;
  pct: number;
}

export interface LlmStatus {
  installed: boolean;
  running: boolean;
  model_ready: boolean;
  model: string;
  message: string;
}

/** "model-download" event: the engine is downloading a speech/voice/Gujarati/speaker model. */
export interface ModelDownload {
  what: string;
  done_mb: number;
  total_mb: number | null;
}

/** First-run speech-engine setup progress ("engine-setup" event, and SetupStatus while it runs). */
export interface InstallProgress {
  step: string;
  pct: number;
  detail: string;
}

export interface SetupStatus {
  engine_installed: boolean;
  /** The engine's Python and packages are already here; setup just didn't finish
   * (finishing downloads only what's missing). Voice Desk finishes it at start. */
  engine_partial: boolean;
  /** Optional packs of the first-run engine; null when not set up or in development. */
  engine_packs: { nvidia: boolean; indic: boolean } | null;
  engine: EngineStatus;
  name_set: boolean;
  hf_token_set: boolean;
  voice_profile: boolean;
  llm: LlmStatus;
  /** The speech-engine setup is running (started earlier, maybe from another visit to Settings). */
  installing: boolean;
  /** The task AI download is running. */
  pulling: boolean;
  /** Where the running engine setup is; null when not installing. */
  install_progress: InstallProgress | null;
}

export interface DataPaths {
  app_data: string;
  database: string;
  recordings: string;
  voice_profile: string;
  speech_models: string;
  llm_models: string;
}

export const api = {
  getSettings: () => invoke<Settings>("get_settings"),
  saveSettings: (settings: Settings) => invoke<void>("save_settings", { settings }),
  sessionStatus: () => invoke<SessionStatus>("session_status"),
  sessionToggle: () => invoke<void>("session_toggle"),
  sessionStop: () => invoke<void>("session_stop"),
  sessionSetWriting: (on: boolean) => invoke<void>("session_set_writing", { on }),
  captureToggle: () => invoke<void>("capture_toggle"),
  listDictations: () => invoke<Dictation[]>("list_dictations"),
  deleteDictation: (id: number) => invoke<void>("delete_dictation", { id }),
  dictationAudio: (id: number) => invoke<ArrayBuffer>("dictation_audio", { id }),
  audioLevels: () => invoke<Levels>("audio_levels"),
  startMeeting: (title: string) =>
    invoke<{ id: number; system_audio: boolean; warning: string | null }>("start_meeting", { title }),
  stopMeeting: () => invoke<number>("stop_meeting"),
  activeMeeting: () => invoke<{ id: number; elapsed_s: number } | null>("active_meeting"),
  callPromptAccept: () => invoke<void>("call_prompt_accept"),
  callPromptDismiss: () => invoke<void>("call_prompt_dismiss"),
  watchedCallApps: () => invoke<string>("watched_call_apps"),
  hardwareInfo: () => invoke<Hardware>("hardware_info"),
  resourceUsage: () => invoke<Usage>("resource_usage"),
  modelsInfo: () => invoke<ModelInfo[]>("models_info"),
  diskUsage: () => invoke<DiskUsage>("disk_usage"),
  search: (query: string) => invoke<SearchHit[]>("search_all", { query }),
  engineInstall: (packs: { nvidia: boolean; indic: boolean }) => invoke<void>("engine_install", { packs }),
  renameSpeaker: (meetingId: number, from: string, to: string, remember: boolean) =>
    invoke<void>("rename_speaker", { meetingId, from, to, remember }),
  updateTranscriptLine: (meetingId: number, index: number, text: string, words: Word[]) =>
    invoke<void>("update_transcript_line", { meetingId, index, text, words }),
  updateDictationText: (id: number, text: string, words: Word[]) => invoke<void>("update_dictation_text", { id, text, words }),
  deleteModel: (id: string) => invoke<void>("delete_model", { id }),
  reprocessMeeting: (id: number, transcribe: boolean) => invoke<void>("reprocess_meeting", { id, transcribe }),
  listMeetings: () => invoke<Meeting[]>("list_meetings"),
  getTranscript: (id: number) => invoke<Segment[]>("get_transcript", { id }),
  meetingAudio: (id: number, track: "mic" | "system") => invoke<ArrayBuffer>("meeting_audio", { id, track }),
  meetingTracks: (id: number) => invoke<{ mic: boolean; system: boolean }>("meeting_tracks", { id }),
  dictationFindTasks: (id: number) => invoke<number>("dictation_find_tasks", { id }),
  dictationToMeeting: (id: number) => invoke<number>("dictation_to_meeting", { id }),
  meetingToDictation: (id: number) => invoke<Dictation>("meeting_to_dictation", { id }),
  renameMeeting: (id: number, title: string) => invoke<void>("rename_meeting", { id, title }),
  deleteMeeting: (id: number) => invoke<void>("delete_meeting", { id }),
  listTasks: (meetingId: number | null = null) => invoke<Task[]>("list_tasks", { meetingId }),
  setTaskDone: (id: number, done: boolean) => invoke<void>("set_task_done", { id, done }),
  updateTask: (id: number, description: string, due: string | null) =>
    invoke<void>("update_task", { id, description, due }),
  addTask: (meetingId: number | null, description: string, due: string | null) =>
    invoke<void>("add_task", { meetingId, description, due }),
  deleteTask: (id: number) => invoke<void>("delete_task", { id }),
  reorderTasks: (ids: number[]) => invoke<void>("reorder_tasks", { ids }),
  voiceProfileInfo: () => invoke<{ exists: boolean; created_at: string | null }>("voice_profile_info"),
  enrollStart: () => invoke<void>("enroll_start"),
  enrollStop: (save: boolean) =>
    invoke<{ seconds: number; consistency: number } | null>("enroll_stop", { save }),
  deleteVoiceProfile: () => invoke<void>("delete_voice_profile"),
  setupStatus: () => invoke<SetupStatus>("setup_status"),
  llmPull: () => invoke<void>("llm_pull"),
  dataPaths: () => invoke<DataPaths>("data_paths"),
  openFolder: (path: string) => invoke<void>("open_folder", { path }),
  engineState: () => invoke<EngineStatus>("engine_state"),
  engineRestart: () => invoke<void>("engine_restart"),
};

/** Subscribe to a backend event for the lifetime of the component. */
export function useEvent<T>(name: string, handler: (payload: T) => void) {
  const latest = useRef(handler);
  latest.current = handler;
  useEffect(() => {
    let unlisten: UnlistenFn | undefined;
    let cancelled = false;
    listen<T>(name, (e) => latest.current(e.payload)).then((u) => {
      if (cancelled) u();
      else unlisten = u;
    });
    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [name]);
}

/** A playable Blob for recording bytes: FLAC (compressed recordings) or WAV. */
export function audioBlob(bytes: ArrayBuffer): Blob {
  const head = new Uint8Array(bytes, 0, Math.min(4, bytes.byteLength));
  const flac = String.fromCharCode(...head) === "fLaC";
  return new Blob([bytes], { type: flac ? "audio/flac" : "audio/wav" });
}

export function formatDuration(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}` : `${m}:${String(sec).padStart(2, "0")}`;
}

/** A running clock: whole seconds passed (never rounded up), "4:05" or "1:02:03". */
export function formatClock(seconds: number): string {
  return formatDuration(Math.floor(Math.max(0, seconds)));
}

export function formatDate(iso: string): string {
  return new Date(iso).toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/** First phrase of a comma-separated command list: "record task, record tasks" -> "record task". */
export function firstPhrase(phrases: string): string {
  return phrases.split(",")[0]?.trim() ?? "";
}
