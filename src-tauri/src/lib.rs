mod audio;
mod db;
mod engine;
mod hardware;
mod insert;
mod jumplist;
mod llm;
mod meeting_detect;
mod overlay;
mod pipeline;
mod session;

use std::path::PathBuf;
use std::sync::atomic::AtomicU64;
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::{json, Value};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use audio::{Recording, Source};
use db::{Db, Dictation, Meeting, NewTask, Segment, Settings, Task};
use engine::Engine;
use llm::{Llm, LlmStatus};
use session::Work;

type CmdResult<T> = Result<T, String>;

fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

pub struct ActiveMeeting {
    pub id: i64,
    mic: Recording,
    system: Option<Recording>,
    pub started: Instant,
}

pub struct AppState {
    pub db: Db,
    pub engine: Arc<Engine>,
    pub llm: Llm,
    data_dir: PathBuf,
    recordings_dir: PathBuf,
    pub session: Mutex<Option<session::Session>>,
    pub next_sid: AtomicU64,
    /// Task recordings still being processed.
    pub processing: AtomicU64,
    pub work: Sender<Work>,
    pub meeting: Mutex<Option<ActiveMeeting>>,
    /// The call going on right now (a call app using the mic), if any.
    pub call: Mutex<Option<meeting_detect::Call>>,
    /// The call the overlay is offering to transcribe.
    pub call_prompt: Mutex<Option<meeting_detect::Call>>,
    /// ✕ on the offer: don't offer this call again (picked up by the detector).
    pub call_dismiss: Mutex<Option<String>>,
    enroll: Mutex<Option<Recording>>,
    pub overlay_pos: Mutex<Option<(i32, i32)>>,
    engine_status: Mutex<Value>,
}

impl AppState {
    pub fn voice_profile_path(&self) -> PathBuf {
        self.data_dir.join("voice_profile.npy")
    }

    pub fn recordings_dir(&self) -> &PathBuf {
        &self.recordings_dir
    }

    pub fn meeting_paths(&self, id: i64) -> (PathBuf, PathBuf) {
        (
            self.recordings_dir.join(format!("meeting-{id}-mic.wav")),
            self.recordings_dir.join(format!("meeting-{id}-system.wav")),
        )
    }
}

pub type Shared = Arc<AppState>;

fn set_engine_status(app: &AppHandle, st: &AppState, status: Value) {
    *st.engine_status.lock().unwrap() = status.clone();
    let _ = app.emit("engine-status", status);
}

// --------------------------------------------------------------------------- //
// Hotkey
// --------------------------------------------------------------------------- //

/// Tracks presses for the double-press and long-press shortcut modes.
#[derive(Default)]
struct KeyState {
    last_press: Option<Instant>,
    /// Incremented on every press/release; a pending long-press only fires if unchanged.
    generation: u64,
}

const DOUBLE_PRESS_WINDOW: Duration = Duration::from_millis(450);

fn register_hotkey(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let gs = app.global_shortcut();
    gs.unregister_all().map_err(err)?;
    let mode = settings.dictation_mode.clone();
    let long_press = Duration::from_secs_f32(settings.long_press_s.clamp(0.5, 10.0));
    let keys = Arc::new(Mutex::new(KeyState::default()));
    gs.on_shortcut(settings.dictation_hotkey.as_str(), move |app, _shortcut, event| {
        let st = app.state::<Shared>().inner().clone();
        let pressed = event.state() == ShortcutState::Pressed;
        let result = match (mode.as_str(), pressed) {
            // Push-to-talk: listen only while the keys are held.
            ("hold", true) => session::start(app, &st),
            ("hold", false) => {
                session::stop(app, &st);
                Ok(())
            }
            // Double-press to start, double-press to stop.
            ("double", true) => {
                let mut k = keys.lock().unwrap();
                let now = Instant::now();
                if k.last_press.is_some_and(|t| now - t <= DOUBLE_PRESS_WINDOW) {
                    k.last_press = None;
                    drop(k);
                    session::toggle(app, &st)
                } else {
                    k.last_press = Some(now);
                    Ok(())
                }
            }
            // Hold for N seconds to start, again to stop (hard to trigger by accident).
            ("long", true) => {
                let generation = {
                    let mut k = keys.lock().unwrap();
                    k.generation += 1;
                    k.generation
                };
                let (app, keys) = (app.clone(), keys.clone());
                std::thread::spawn(move || {
                    std::thread::sleep(long_press);
                    if keys.lock().unwrap().generation == generation {
                        let st = app.state::<Shared>().inner().clone();
                        if let Err(e) = session::toggle(&app, &st) {
                            let _ = app.emit("session-notice", json!({ "message": e }));
                        }
                    }
                });
                Ok(())
            }
            ("long", false) => {
                keys.lock().unwrap().generation += 1; // released early: cancel
                Ok(())
            }
            // Default: press once to start, once to stop.
            (_, true) => session::toggle(app, &st),
            (_, false) => Ok(()),
        };
        if let Err(e) = result {
            let _ = app.emit("session-notice", json!({ "message": e }));
        }
    })
    .map_err(|e| format!("Could not register hotkey '{}': {e}", settings.dictation_hotkey))
}

/// Put the most recent dictation on the clipboard (tray menu, taskbar menu).
fn copy_last_dictation(app: &AppHandle) {
    let st = app.state::<Shared>();
    let message = match st.db.dictations(1).ok().and_then(|d| d.into_iter().next()) {
        None => "Nothing dictated yet".to_string(),
        Some(d) => match arboard::Clipboard::new().and_then(|mut c| c.set_text(d.text.clone())) {
            Ok(()) => "Last dictation copied".to_string(),
            Err(e) => format!("Couldn't copy: {e}"),
        },
    };
    let _ = app.emit("session-notice", json!({ "message": message }));
}

// --------------------------------------------------------------------------- //
// Commands: settings & session
// --------------------------------------------------------------------------- //

#[tauri::command]
fn get_settings(st: State<Shared>) -> CmdResult<Settings> {
    st.db.settings().map_err(err)
}

#[tauri::command]
fn save_settings(app: AppHandle, st: State<Shared>, settings: Settings) -> CmdResult<()> {
    let old = st.db.settings().map_err(err)?;
    let keys = settings.dictation_hotkey.split('+').filter(|k| !k.trim().is_empty()).count();
    if !(1..=3).contains(&keys) {
        return Err("The shortcut must use 1 to 3 keys".into());
    }
    if let Err(e) = register_hotkey(&app, &settings) {
        let _ = register_hotkey(&app, &old); // keep the previous working hotkey
        return Err(e);
    }
    st.db.save_settings(&settings).map_err(err)?;
    let _ = st.engine.start_request("configure", json!({ "unload_after_min": settings.unload_after_min }), None);
    if old.whisper_model != settings.whisper_model
        || old.whisper_device != settings.whisper_device
        || old.langs() != settings.langs()
    {
        warm_up_engine(app.clone(), st.inner().clone());
    }
    // Apply name/command/vocabulary changes to a session that's already listening.
    if let Some(sid) = st.session.lock().unwrap().as_ref().map(|s| s.sid) {
        let mut args = json!({
            "sid": sid,
            "wake_name": settings.assistant_name,
            "commands": settings.commands(),
            "vocabulary": settings.whisper_vocabulary(),
            "language": settings.language,
            "silence_ms": settings.silence_ms,
        });
        session::merge_json(&mut args, settings.language_options());
        let _ = st.engine.start_request("stream_update", args, None);
    }
    session::emit_status(&app, st.inner());
    Ok(())
}

#[tauri::command]
fn session_status(st: State<Shared>) -> session::Status {
    session::status(st.inner())
}

#[tauri::command]
fn session_toggle(app: AppHandle, st: State<Shared>) -> CmdResult<()> {
    session::toggle(&app, st.inner())
}

#[tauri::command]
fn session_stop(app: AppHandle, st: State<Shared>) {
    session::stop(&app, st.inner());
}

#[tauri::command]
fn session_set_writing(app: AppHandle, st: State<Shared>, on: bool) {
    session::set_writing(&app, st.inner(), on);
}

#[tauri::command]
fn capture_toggle(app: AppHandle, st: State<Shared>) -> CmdResult<()> {
    session::toggle_capture(&app, st.inner())
}

#[tauri::command]
fn list_dictations(st: State<Shared>) -> CmdResult<Vec<Dictation>> {
    st.db.dictations(200).map_err(err)
}

#[tauri::command]
fn delete_dictation(st: State<Shared>, id: i64) -> CmdResult<()> {
    if let Some(audio) = st.db.delete_dictation(id).map_err(err)? {
        let _ = std::fs::remove_file(audio);
    }
    Ok(())
}

/// The recording of a listening session, as WAV bytes for the History player.
#[tauri::command]
fn dictation_audio(st: State<Shared>, id: i64) -> CmdResult<tauri::ipc::Response> {
    let path = st.db.dictation_audio_path(id).map_err(err)?.ok_or("This entry has no recording")?;
    let bytes = std::fs::read(&path).map_err(|e| format!("Recording not found: {e}"))?;
    Ok(tauri::ipc::Response::new(bytes))
}

#[derive(Serialize)]
struct Levels {
    listening: Option<f32>,
    mic: Option<f32>,
    system: Option<f32>,
    enroll: Option<f32>,
}

#[tauri::command]
fn audio_levels(st: State<Shared>) -> Levels {
    let listening = st.session.lock().unwrap().as_ref().and_then(|s| s.mic_level());
    let enroll = st.enroll.lock().unwrap().as_ref().map(|r| r.level());
    let m = st.meeting.lock().unwrap();
    Levels {
        listening,
        mic: m.as_ref().map(|m| m.mic.level()),
        system: m.as_ref().and_then(|m| m.system.as_ref().map(|s| s.level())),
        enroll,
    }
}

// --------------------------------------------------------------------------- //
// Commands: meetings
// --------------------------------------------------------------------------- //

#[derive(Serialize)]
struct StartedMeeting {
    id: i64,
    system_audio: bool,
    warning: Option<String>,
}

#[tauri::command]
fn start_meeting(app: AppHandle, st: State<Shared>, title: String) -> CmdResult<StartedMeeting> {
    begin_meeting(&app, st.inner(), &title)
}

/// Start recording a meeting: the mic (you) and the speakers (everyone else).
pub(crate) fn begin_meeting(app: &AppHandle, st: &Shared, title: &str) -> CmdResult<StartedMeeting> {
    let started = begin_meeting_inner(app, st, title);
    *st.call_prompt.lock().unwrap() = None;
    session::emit_status(app, st);
    started
}

fn begin_meeting_inner(app: &AppHandle, st: &Shared, title: &str) -> CmdResult<StartedMeeting> {
    let mut slot = st.meeting.lock().unwrap();
    if slot.is_some() {
        return Err("A meeting is already being recorded".into());
    }
    let title = if title.trim().is_empty() {
        format!("Meeting {}", chrono::Local::now().format("%b %d, %H:%M"))
    } else {
        title.trim().to_string()
    };
    let id = st.db.create_meeting(&title, "meeting").map_err(err)?;
    let (mic_path, sys_path) = st.meeting_paths(id);

    let mic = match Recording::to_file(Source::Microphone, &mic_path) {
        Ok(r) => r,
        Err(e) => {
            let _ = st.db.set_meeting_status(id, "error", Some(&e.to_string()));
            let _ = app.emit("meetings-changed", ());
            return Err(format!("Microphone error: {e}"));
        }
    };
    let (system, warning) = match Recording::to_file(Source::System, &sys_path) {
        Ok(r) => (Some(r), None),
        Err(e) => (None, Some(format!("System audio unavailable, recording microphone only: {e}"))),
    };
    let system_audio = system.is_some();
    *slot = Some(ActiveMeeting { id, mic, system, started: Instant::now() });
    let _ = app.emit("meetings-changed", ());
    Ok(StartedMeeting { id, system_audio, warning })
}

#[tauri::command]
async fn stop_meeting(app: AppHandle, st: State<'_, Shared>) -> CmdResult<i64> {
    end_meeting(&app, st.inner()).await
}

/// Stop recording the meeting, then transcribe it and find tasks in the background.
pub(crate) async fn end_meeting(app: &AppHandle, st: &Shared) -> CmdResult<i64> {
    let active = st.meeting.lock().unwrap().take().ok_or("No meeting is being recorded")?;
    session::emit_status(app, st);
    let _ = app.emit("meetings-changed", ());
    let id = active.id;
    tauri::async_runtime::spawn_blocking(move || {
        active.mic.stop()?;
        if let Some(s) = active.system {
            s.stop()?;
        }
        anyhow::Ok(())
    })
    .await
    .map_err(err)?
    .map_err(err)?;
    let (app, st) = (app.clone(), st.clone());
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st, id, pipeline::Input::Recording).await;
    });
    Ok(id)
}

#[tauri::command]
fn active_meeting(st: State<Shared>) -> Option<Value> {
    st.meeting.lock().unwrap().as_ref().map(|m| json!({ "id": m.id, "elapsed_s": m.started.elapsed().as_secs_f64() }))
}

/// "Transcribe Meeting" on the overlay's call offer.
#[tauri::command]
fn call_prompt_accept(app: AppHandle, st: State<Shared>) -> CmdResult<()> {
    accept_call(&app, st.inner())
}

/// Record the call the overlay is offering (its button, or the shortcut).
pub(crate) fn accept_call(app: &AppHandle, st: &Shared) -> CmdResult<()> {
    let call = st.call_prompt.lock().unwrap().clone().ok_or("The call has ended")?;
    // A meeting recording takes over from dictation.
    session::stop(app, st);
    let title = format!("{} call · {}", call.app, chrono::Local::now().format("%b %d, %H:%M"));
    let started = begin_meeting(app, st, &title)?;
    let message = started.warning.unwrap_or_else(|| format!("Recording the {} call", call.app));
    let _ = app.emit("session-notice", json!({ "message": message, "short": "● Recording" }));
    Ok(())
}

/// ✕ on the call offer: not for this call.
#[tauri::command]
fn call_prompt_dismiss(app: AppHandle, st: State<Shared>) {
    if let Some(call) = st.call_prompt.lock().unwrap().take() {
        *st.call_dismiss.lock().unwrap() = Some(call.key);
    }
    session::emit_status(&app, st.inner());
}

#[tauri::command]
async fn hardware_info() -> hardware::Hardware {
    tauri::async_runtime::spawn_blocking(hardware::info).await.expect("hardware info")
}

#[tauri::command]
async fn resource_usage() -> hardware::Usage {
    tauri::async_runtime::spawn_blocking(hardware::usage).await.expect("resource usage")
}

#[tauri::command]
fn watched_call_apps() -> &'static str {
    meeting_detect::WATCHED
}

/// Re-run the pipeline. `transcribe = false` only re-extracts tasks (e.g. after changing your name).
#[tauri::command]
fn reprocess_meeting(app: AppHandle, st: State<Shared>, id: i64, transcribe: bool) -> CmdResult<()> {
    let input = if transcribe {
        let (mic, sys) = st.meeting_paths(id);
        if !mic.exists() && !sys.exists() {
            return Err("The audio for this recording is no longer available".into());
        }
        pipeline::Input::Recording
    } else {
        pipeline::Input::Reextract
    };
    let st = st.inner().clone();
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st, id, input).await;
    });
    Ok(())
}

/// One of a meeting's two recordings: "mic" (you) or "system" (the computer's audio).
#[tauri::command]
fn meeting_audio(st: State<Shared>, id: i64, track: String) -> CmdResult<tauri::ipc::Response> {
    let (mic, system) = st.meeting_paths(id);
    let path = if track == "system" { system } else { mic };
    let bytes = std::fs::read(&path).map_err(|_| "This recording is not available".to_string())?;
    Ok(tauri::ipc::Response::new(bytes))
}

#[derive(Serialize)]
struct MeetingTracks {
    mic: bool,
    system: bool,
}

#[tauri::command]
fn meeting_tracks(st: State<Shared>, id: i64) -> MeetingTracks {
    let (mic, system) = st.meeting_paths(id);
    MeetingTracks { mic: mic.exists(), system: system.exists() }
}

/// Find tasks in a Listen recording. The tasks are grouped under a hidden
/// "dictation" entry so they show where they came from on the Tasks page.
#[tauri::command]
async fn dictation_find_tasks(app: AppHandle, st: State<'_, Shared>, id: i64) -> CmdResult<usize> {
    let d = st
        .db
        .dictations(10_000)
        .map_err(err)?
        .into_iter()
        .find(|d| d.id == id)
        .ok_or("Recording not found")?;
    let when = chrono::DateTime::parse_from_rfc3339(&d.created_at)
        .map(|t| t.format("%b %d, %H:%M").to_string())
        .unwrap_or_default();
    // Tasks already found: don't add the same ones again. If they were all
    // deleted, look again into the same meeting rather than a new one.
    if !d.tasks.is_empty() {
        return Ok(d.tasks.len());
    }
    let meeting_id = match d.meeting_id {
        Some(m) => m,
        None => {
            let m = st.db.create_meeting(&format!("Recording · {when}"), "dictation").map_err(err)?;
            st.db.set_dictation_meeting(id, m).map_err(err)?;
            m
        }
    };
    let duration = d.duration_ms as f64 / 1000.0;
    let words = serde_json::from_value(d.words).ok();
    let segment = Segment { start: 0.0, end: duration, speaker: "Me".into(), text: d.text, words };
    st.db.save_transcript(meeting_id, &[segment], duration).map_err(err)?;
    pipeline::process(app, st.inner().clone(), meeting_id, pipeline::Input::Reextract).await
}

/// "Make it a meeting": re-transcribe a Listen recording with speaker detection.
#[tauri::command]
fn dictation_to_meeting(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<i64> {
    let d = st.db.dictations(10_000).map_err(err)?.into_iter().find(|d| d.id == id).ok_or("Recording not found")?;
    if !d.has_audio {
        return Err("This recording's audio was already deleted, so it can't be transcribed again".into());
    }
    let when = chrono::DateTime::parse_from_rfc3339(&d.created_at)
        .map(|t| t.format("%b %d, %H:%M").to_string())
        .unwrap_or_default();
    let (meeting_id, audio) = st.db.dictation_into_meeting(id, &format!("Meeting · {when}")).map_err(err)?;
    let (mic, sys) = st.meeting_paths(meeting_id);
    let _ = std::fs::remove_file(&sys);
    if let Some(audio) = audio {
        if std::fs::rename(&audio, &mic).is_err() {
            std::fs::copy(&audio, &mic).map_err(|e| format!("Couldn't move the recording: {e}"))?;
            let _ = std::fs::remove_file(&audio);
        }
    }
    let _ = app.emit("meetings-changed", ());
    let _ = app.emit("tasks-changed", ());
    let st2 = st.inner().clone();
    tauri::async_runtime::spawn(async move {
        let _ = pipeline::process(app, st2, meeting_id, pipeline::Input::Recording).await;
    });
    Ok(meeting_id)
}

/// "Move to Listen history": one recording (both tracks mixed), words from the transcript.
#[tauri::command]
fn meeting_to_dictation(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<Dictation> {
    let m = st.db.meeting(id).map_err(err)?.ok_or("Meeting not found")?;
    if !matches!(m.status.as_str(), "done" | "error") {
        return Err("Wait until the meeting has finished processing".into());
    }
    let segments = st.db.transcript(id).map_err(err)?;
    let mut words: Vec<Value> = Vec::new();
    for s in &segments {
        match &s.words {
            Some(ws) if !ws.is_empty() => words.extend(ws.iter().map(|w| json!({ "w": w.w, "s": w.s, "e": w.e }))),
            // Older transcripts: spread the line's time over its words.
            _ => {
                let parts: Vec<&str> = s.text.split_whitespace().collect();
                let total: usize = parts.iter().map(|p| p.chars().count() + 1).sum::<usize>().max(1);
                let mut t = s.start;
                for p in parts {
                    let d = (s.end - s.start) * (p.chars().count() + 1) as f64 / total as f64;
                    words.push(json!({ "w": p, "s": t, "e": t + d }));
                    t += d;
                }
            }
        }
    }
    let text = segments.iter().map(|s| s.text.trim()).collect::<Vec<_>>().join(" ");

    let (mic, sys) = st.meeting_paths(id);
    let tracks: Vec<&std::path::Path> = [mic.as_path(), sys.as_path()].into_iter().filter(|p| p.exists()).collect();
    let audio = if tracks.is_empty() {
        None
    } else {
        let out = st
            .recordings_dir()
            .join(format!("listen-{}-m{id}.wav", chrono::Local::now().format("%Y%m%d-%H%M%S")));
        audio::mix_wavs(&tracks, &out).map_err(err)?;
        Some(out)
    };
    let duration_ms = (m.duration_s.unwrap_or(0.0) * 1000.0) as i64;
    let did = match st.db.meeting_into_dictation(id, &text, duration_ms, audio.as_deref(), &Value::Array(words)) {
        Ok(did) => did,
        Err(e) => {
            if let Some(a) = &audio {
                let _ = std::fs::remove_file(a);
            }
            return Err(err(e));
        }
    };
    for t in tracks {
        let _ = std::fs::remove_file(t);
    }
    let d = st.db.dictations(10_000).map_err(err)?.into_iter().find(|d| d.id == did).ok_or("Recording not found")?;
    let _ = app.emit("meetings-changed", ());
    let _ = app.emit("tasks-changed", ());
    Ok(d)
}

#[tauri::command]
fn list_meetings(st: State<Shared>) -> CmdResult<Vec<Meeting>> {
    st.db.meetings().map_err(err)
}

#[tauri::command]
fn get_transcript(st: State<Shared>, id: i64) -> CmdResult<Vec<Segment>> {
    st.db.transcript(id).map_err(err)
}

#[tauri::command]
fn rename_meeting(st: State<Shared>, id: i64, title: String) -> CmdResult<()> {
    st.db.rename_meeting(id, &title).map_err(err)
}

#[tauri::command]
fn delete_meeting(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<()> {
    if st.meeting.lock().unwrap().as_ref().map(|m| m.id) == Some(id) {
        return Err("Stop the recording first".into());
    }
    let (mic, sys) = st.meeting_paths(id);
    let _ = std::fs::remove_file(mic);
    let _ = std::fs::remove_file(sys);
    st.db.delete_meeting(id).map_err(err)?;
    // Its tasks went with it.
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

// --------------------------------------------------------------------------- //
// Commands: tasks
// --------------------------------------------------------------------------- //

#[tauri::command]
fn list_tasks(st: State<Shared>, meeting_id: Option<i64>) -> CmdResult<Vec<Task>> {
    st.db.tasks(meeting_id).map_err(err)
}

#[tauri::command]
fn set_task_done(st: State<Shared>, id: i64, done: bool) -> CmdResult<()> {
    st.db.set_task_done(id, done).map_err(err)
}

#[tauri::command]
fn update_task(app: AppHandle, st: State<Shared>, id: i64, description: String, due: Option<String>) -> CmdResult<()> {
    let due = due.filter(|d| !d.trim().is_empty());
    st.db.update_task(id, description.trim(), due.as_deref()).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

#[tauri::command]
fn add_task(st: State<Shared>, meeting_id: Option<i64>, description: String, due: Option<String>) -> CmdResult<()> {
    st.db
        .add_task(meeting_id, &NewTask { description, assigned_by: Some("Self".into()), due, quote: None })
        .map_err(err)
}

#[tauri::command]
fn delete_task(app: AppHandle, st: State<Shared>, id: i64) -> CmdResult<()> {
    st.db.delete_task(id).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

#[tauri::command]
fn reorder_tasks(app: AppHandle, st: State<Shared>, ids: Vec<i64>) -> CmdResult<()> {
    st.db.reorder_tasks(&ids).map_err(err)?;
    let _ = app.emit("tasks-changed", ());
    Ok(())
}

// --------------------------------------------------------------------------- //
// Commands: voice profile
// --------------------------------------------------------------------------- //

#[derive(Serialize)]
struct VoiceProfile {
    exists: bool,
    created_at: Option<String>,
}

#[tauri::command]
fn voice_profile_info(st: State<Shared>) -> VoiceProfile {
    let path = st.voice_profile_path();
    let created_at = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .map(|t| chrono::DateTime::<chrono::Local>::from(t).to_rfc3339());
    VoiceProfile { exists: path.exists(), created_at }
}

#[tauri::command]
fn enroll_start(st: State<Shared>) -> CmdResult<()> {
    let mut slot = st.enroll.lock().unwrap();
    if slot.is_none() {
        let path = st.data_dir.join("voice_enroll.wav");
        *slot = Some(Recording::to_file(Source::Microphone, &path).map_err(|e| format!("Microphone error: {e}"))?);
    }
    Ok(())
}

#[tauri::command]
async fn enroll_stop(app: AppHandle, st: State<'_, Shared>, save: bool) -> CmdResult<Value> {
    let rec = st.enroll.lock().unwrap().take().ok_or("Not recording")?;
    tauri::async_runtime::spawn_blocking(move || rec.stop()).await.map_err(err)?.map_err(err)?;
    let wav = st.data_dir.join("voice_enroll.wav");
    if !save {
        let _ = std::fs::remove_file(&wav);
        return Ok(Value::Null);
    }
    let profile = st.voice_profile_path();
    let res = st.engine.request("enroll", json!({ "path": wav, "out": profile }), None).await;
    let _ = std::fs::remove_file(&wav);
    let res = res.map_err(err)?;
    if let Some(sid) = st.session.lock().unwrap().as_ref().map(|s| s.sid) {
        let _ = st.engine.start_request("stream_update", json!({ "sid": sid, "voice_profile": profile }), None);
    }
    session::emit_status(&app, st.inner());
    Ok(res)
}

#[tauri::command]
fn delete_voice_profile(st: State<Shared>) -> CmdResult<()> {
    let path = st.voice_profile_path();
    if path.exists() {
        std::fs::remove_file(&path).map_err(err)?;
    }
    if let Some(sid) = st.session.lock().unwrap().as_ref().map(|s| s.sid) {
        let _ = st.engine.start_request("stream_update", json!({ "sid": sid, "voice_profile": null }), None);
    }
    Ok(())
}

// --------------------------------------------------------------------------- //
// Commands: setup & engine
// --------------------------------------------------------------------------- //

#[derive(Serialize)]
struct SetupStatus {
    engine_installed: bool,
    engine: Value,
    name_set: bool,
    hf_token_set: bool,
    voice_profile: bool,
    llm: LlmStatus,
}

#[tauri::command]
async fn setup_status(st: State<'_, Shared>) -> CmdResult<SetupStatus> {
    let s = st.db.settings().map_err(err)?;
    let engine = st.engine_status.lock().unwrap().clone();
    Ok(SetupStatus {
        engine_installed: st.engine.is_installed(),
        engine,
        name_set: !s.user_name.trim().is_empty(),
        hf_token_set: !s.hf_token.trim().is_empty(),
        voice_profile: st.voice_profile_path().exists(),
        llm: st.llm.status(&s).await,
    })
}

#[tauri::command]
async fn llm_pull(app: AppHandle, st: State<'_, Shared>) -> CmdResult<()> {
    let s = st.db.settings().map_err(err)?;
    let mut last = -10.0;
    st.llm
        .pull(&s, |status, pct| {
            // Throttle UI updates to whole-percent steps.
            if pct < 0.0 || pct - last >= 1.0 || pct >= 100.0 {
                last = pct;
                let _ = app.emit("llm-pull", json!({ "status": status, "pct": pct }));
            }
        })
        .await
        .map_err(err)
}

#[derive(Serialize)]
struct DataPaths {
    app_data: PathBuf,
    database: PathBuf,
    recordings: PathBuf,
    voice_profile: PathBuf,
    speech_models: PathBuf,
    llm_models: PathBuf,
}

fn home_dir() -> PathBuf {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(PathBuf::from).unwrap_or_default()
}

#[tauri::command]
fn data_paths(st: State<Shared>) -> DataPaths {
    let hf = std::env::var_os("HF_HOME")
        .map(|h| PathBuf::from(h).join("hub"))
        .unwrap_or_else(|| home_dir().join(".cache").join("huggingface").join("hub"));
    let ollama = std::env::var_os("OLLAMA_MODELS")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".ollama").join("models"));
    DataPaths {
        app_data: st.data_dir.clone(),
        database: st.data_dir.join("voicedesk.db"),
        recordings: st.recordings_dir.clone(),
        voice_profile: st.voice_profile_path(),
        speech_models: hf,
        llm_models: ollama,
    }
}

#[tauri::command]
fn open_folder(app: AppHandle, path: String) -> CmdResult<()> {
    use tauri_plugin_opener::OpenerExt;
    app.opener().open_path(path, None::<&str>).map_err(err)
}

#[tauri::command]
fn overlay_resize(app: AppHandle, width: f64, height: f64) {
    overlay::resize(&app, width, height);
}

#[tauri::command]
fn engine_state(st: State<Shared>) -> Value {
    st.engine_status.lock().unwrap().clone()
}

#[tauri::command]
fn engine_restart(app: AppHandle, st: State<Shared>) {
    st.engine.shutdown();
    warm_up_engine(app, st.inner().clone());
}

// --------------------------------------------------------------------------- //
// Setup
// --------------------------------------------------------------------------- //

/// Dev default: the project's .venv and engine/ folder. Override with env vars.
fn engine_paths() -> (PathBuf, PathBuf) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf();
    // venv layout differs: Scripts\python.exe on Windows, bin/python on macOS/Linux.
    let venv_python = if cfg!(windows) {
        root.join(".venv").join("Scripts").join("python.exe")
    } else {
        root.join(".venv").join("bin").join("python")
    };
    let python = std::env::var_os("VOICEDESK_PYTHON").map(PathBuf::from).unwrap_or(venv_python);
    let script = std::env::var_os("VOICEDESK_ENGINE")
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("engine").join("engine.py"));
    (python, script)
}

fn warm_up_engine(app: AppHandle, st: Shared) {
    tauri::async_runtime::spawn(async move {
        if !st.engine.is_installed() {
            set_engine_status(
                &app,
                &st,
                json!({ "state": "error", "message": "Speech engine is not set up. Run the setup script in the project folder." }),
            );
            return;
        }
        set_engine_status(&app, &st, json!({ "state": "loading" }));
        let s = st.db.settings().unwrap_or_default();
        let _ = st.engine.request("configure", json!({ "unload_after_min": s.unload_after_min }), None).await;
        let res = st
            .engine
            .request(
                "load",
                json!({ "model": s.whisper_model, "device": s.whisper_device, "languages": s.langs() }),
                None,
            )
            .await;
        let payload = match res {
            Ok(v) => json!({ "state": "ready", "device": v["device"], "model": v["model"] }),
            Err(e) => json!({ "state": "error", "message": e.to_string() }),
        };
        set_engine_status(&app, &st, payload);
    });
}

/// The window and the floating bar (configured in tauri.conf.json, created
/// here). "CPU only" also keeps the app's own drawing off the GPU: WebView2
/// otherwise runs a GPU process for the interface. All webviews must get the
/// same browser arguments, since they share one browser process.
fn create_windows(app: &tauri::App, settings: &Settings) -> tauri::Result<()> {
    #[allow(unused_mut)]
    let mut args = String::from("--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection");
    if settings.whisper_device == "cpu" {
        args.push_str(" --disable-gpu --disable-gpu-compositing");
    }
    for cfg in app.config().app.windows.clone() {
        let builder = tauri::WebviewWindowBuilder::from_config(app.handle(), &cfg)?;
        #[cfg(windows)]
        let builder = builder.additional_browser_args(&args);
        builder.build()?;
    }
    Ok(())
}

/// Route engine messages that aren't replies (live results, lifecycle).
fn on_engine_event(app: &AppHandle, ev: &Value) {
    let st = app.state::<Shared>().inner().clone();
    let sid = ev["sid"].as_u64().unwrap_or(0);
    match ev["event"].as_str() {
        Some("utterance") => {
            let _ = st.work.send(Work::Utterance(ev.clone()));
        }
        Some("stream_ready") => {
            set_engine_status(app, &st, json!({ "state": "ready", "device": ev["device"], "model": ev["model"] }));
            let _ = st.work.send(Work::Ready(sid));
        }
        Some("stream_error") => {
            let msg = ev["message"].as_str().unwrap_or("unknown error").to_string();
            let _ = st.work.send(Work::Failed(sid, msg));
        }
        Some("sleeping") => set_engine_status(app, &st, json!({ "state": "sleeping" })),
        Some("exited") => {
            if st.engine_status.lock().unwrap()["state"] != "sleeping" {
                set_engine_status(app, &st, json!({ "state": "sleeping" }));
            }
            if let Some(sid) = st.session.lock().unwrap().as_ref().map(|s| s.sid) {
                let _ = st.work.send(Work::Failed(sid, "the speech engine stopped".into()));
            }
        }
        _ => {}
    }
}

/// Everything Voice Desk started stops with it: speech engine, Ollama, recordings.
fn shutdown_services(app: &AppHandle) {
    let st = app.state::<Shared>();
    overlay::save(st.inner());
    session::stop(app, st.inner());
    st.engine.shutdown();
    st.llm.shutdown();
}

fn quit(app: &AppHandle) {
    shutdown_services(app);
    app.exit(0);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        // Launching Voice Desk again just brings up the running window.
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            if args.iter().any(|a| a == jumplist::COPY_LAST_ARG) {
                copy_last_dictation(app);
                return;
            }
            if let Some(w) = app.get_webview_window("main") {
                let _ = w.show();
                let _ = w.unminimize();
                let _ = w.set_focus();
            }
        }))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            let recordings_dir = data_dir.join("recordings");
            std::fs::create_dir_all(&recordings_dir)?;
            let db = Db::open(&data_dir.join("voicedesk.db"))?;
            let settings = db.settings()?;
            create_windows(app, &settings)?;
            if settings.keep_audio_days > 0 {
                for old in db.expire_dictation_audio(settings.keep_audio_days).unwrap_or_default() {
                    let _ = std::fs::remove_file(old);
                }
            }
            let (python, script) = engine_paths();
            let (work_tx, work_rx) = std::sync::mpsc::channel();

            let state: Shared = Arc::new(AppState {
                db,
                engine: Arc::new(Engine::new(python, script)),
                llm: Llm::new(),
                data_dir,
                recordings_dir,
                session: Mutex::new(None),
                next_sid: AtomicU64::new(1),
                processing: AtomicU64::new(0),
                work: work_tx,
                meeting: Mutex::new(None),
                call: Mutex::new(None),
                call_prompt: Mutex::new(None),
                call_dismiss: Mutex::new(None),
                enroll: Mutex::new(None),
                overlay_pos: Mutex::new(None),
                engine_status: Mutex::new(json!({ "state": "loading" })),
            });
            app.manage(state.clone());

            let handle = app.handle().clone();
            state.engine.on_global_event(move |ev| on_engine_event(&handle, ev));
            let (handle, st) = (app.handle().clone(), state.clone());
            std::thread::Builder::new()
                .name("session-worker".into())
                .spawn(move || session::worker(handle, st, work_rx))?;
            meeting_detect::watch(app.handle().clone(), state.clone());

            if let Err(e) = register_hotkey(app.handle(), &settings) {
                eprintln!("{e}");
            }
            if let Err(e) = jumplist::install() {
                eprintln!("[jumplist] {e:?}");
            }
            if std::env::args().any(|a| a == jumplist::COPY_LAST_ARG) {
                copy_last_dictation(app.handle());
            }
            overlay::init(app.handle());
            warm_up_engine(app.handle().clone(), state.clone());
            // Start Ollama now so the first task extraction doesn't wait for it.
            tauri::async_runtime::spawn(async move {
                let s = state.db.settings().unwrap_or_default();
                if let Err(e) = state.llm.ensure_running(&s).await {
                    eprintln!("[ollama] {e}");
                }
            });

            // Tray menu: listen, copy last dictation, open, quit.
            let listen = MenuItem::with_id(app, "listen", "Start / stop listening", true, None::<&str>)?;
            let copy_last = MenuItem::with_id(app, "copy_last", "Copy last dictation", true, None::<&str>)?;
            let show = MenuItem::with_id(app, "show", "Open Voice Desk", true, None::<&str>)?;
            let quit_item = MenuItem::with_id(app, "quit", "Quit Voice Desk", true, None::<&str>)?;
            let sep = tauri::menu::PredefinedMenuItem::separator(app)?;
            let menu = Menu::with_items(app, &[&listen, &copy_last, &sep, &show, &quit_item])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Voice Desk")
                .menu(&menu)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "listen" => {
                        let st = app.state::<Shared>().inner().clone();
                        let _ = session::toggle(app, &st);
                    }
                    "copy_last" => copy_last_dictation(app),
                    "show" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.unminimize();
                            let _ = w.set_focus();
                        }
                    }
                    "quit" => quit(app),
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| match event {
            WindowEvent::CloseRequested { api, .. } if window.label() == "main" => {
                api.prevent_close();
                let app = window.app_handle();
                let keep = app.state::<Shared>().db.settings().map(|s| s.close_to_tray).unwrap_or(false);
                if keep {
                    let _ = window.hide(); // keep running in the tray; the shortcut keeps working
                } else {
                    quit(app);
                }
            }
            WindowEvent::Moved(pos) if window.label() == "overlay" => {
                let st = window.app_handle().state::<Shared>();
                overlay::moved(st.inner(), *pos);
            }
            _ => {}
        })
        .invoke_handler(tauri::generate_handler![
            get_settings,
            save_settings,
            session_status,
            session_toggle,
            session_stop,
            session_set_writing,
            capture_toggle,
            list_dictations,
            delete_dictation,
            dictation_audio,
            data_paths,
            open_folder,
            audio_levels,
            start_meeting,
            stop_meeting,
            active_meeting,
            reprocess_meeting,
            list_meetings,
            get_transcript,
            meeting_audio,
            meeting_tracks,
            dictation_find_tasks,
            rename_meeting,
            delete_meeting,
            call_prompt_accept,
            call_prompt_dismiss,
            watched_call_apps,
            hardware_info,
            resource_usage,
            dictation_to_meeting,
            meeting_to_dictation,
            list_tasks,
            set_task_done,
            update_task,
            add_task,
            delete_task,
            reorder_tasks,
            voice_profile_info,
            enroll_start,
            enroll_stop,
            delete_voice_profile,
            setup_status,
            llm_pull,
            engine_state,
            engine_restart,
            overlay_resize,
        ])
        .build(tauri::generate_context!())
        .expect("error while building Voice Desk")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                shutdown_services(app);
            }
        });
}
