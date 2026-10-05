mod audio;
mod db;
mod downloads;
mod engine;
mod engine_setup;
mod hardware;
mod hotkey;
mod insert;
mod jumplist;
mod llm;
mod meetings;
mod meeting_detect;
mod overlay;
mod pipeline;
mod search;
mod secrets;
mod session;
mod system;
mod tasks;
mod voice;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};

use serde::Serialize;
use serde_json::{json, Value};
use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, State, WindowEvent};

use audio::Recording;
use db::{Db, Dictation, Settings};
use engine::Engine;
use llm::Llm;
use session::Work;

pub(crate) type CmdResult<T> = Result<T, String>;

pub(crate) fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
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
    pub meeting: Mutex<Option<meetings::ActiveMeeting>>,
    /// The call going on right now (a call app using the mic), if any.
    pub call: Mutex<Option<meeting_detect::Call>>,
    /// The call the overlay is offering to transcribe.
    pub call_prompt: Mutex<Option<meeting_detect::Call>>,
    /// ✕ on the offer: don't offer this call again (picked up by the detector).
    pub call_dismiss: Mutex<Option<String>>,
    /// Listening when the offered call started: when it becomes a meeting recording.
    pub call_switch_at: Mutex<Option<std::time::Instant>>,
    /// The shortcut was pressed once during a meeting (a second press stops it).
    pub stop_armed: Mutex<Option<std::time::Instant>>,
    enroll: Mutex<Option<Recording>>,
    pub overlay_pos: Mutex<Option<(i32, i32)>>,
    engine_status: Mutex<Value>,
    /// The engine status a model download interrupted, put back when it ends.
    status_before_download: Mutex<Option<Value>>,
    /// engine_install / llm_pull running (one at a time each).
    pub installing: AtomicBool,
    pub pulling: AtomicBool,
    /// The last "engine-setup" progress while engine_install runs.
    pub install_progress: Mutex<Option<system::SetupProgress>>,
    /// The engine's last "models_in_use" answer and the settings it was for, so
    /// Settings -> Storage doesn't wake a sleeping engine to ask again.
    pub models_in_use: Mutex<Option<(String, Value)>>,
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
    if let Err(e) = hotkey::register_hotkey(&app, &settings) {
        let _ = hotkey::register_hotkey(&app, &old); // keep the previous working hotkey
        return Err(e);
    }
    st.db.save_settings(&settings).map_err(err)?;
    let _ = st.engine.start_request("configure", json!({ "unload_after_min": settings.unload_after_min }), None);
    if old.whisper_model != settings.whisper_model
        || old.device != settings.device
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

/// Opening the microphone can take a second or more: done off the main thread
/// (which draws the windows), in order with the shortcut's starts and stops.
#[tauri::command]
async fn session_toggle(app: AppHandle, st: State<'_, Shared>) -> CmdResult<()> {
    let st = st.inner().clone();
    session::in_order_async(move || session::toggle(&app, &st)).await?
}

#[tauri::command]
fn session_stop(app: AppHandle, st: State<Shared>) {
    session::stop(&app, st.inner());
}

#[tauri::command]
fn session_set_writing(app: AppHandle, st: State<Shared>, on: bool) {
    session::set_writing(&app, st.inner(), on);
}

/// Starting a task recording opens the system audio: off the main thread too.
#[tauri::command]
async fn capture_toggle(app: AppHandle, st: State<'_, Shared>) -> CmdResult<()> {
    let st = st.inner().clone();
    session::in_order_async(move || session::toggle_capture(&app, &st)).await?
}

#[tauri::command]
async fn list_dictations(st: State<'_, Shared>) -> CmdResult<Vec<Dictation>> {
    st.db.dictations(200).map_err(err)
}

/// Clears the "already running" flag however setup ends.
struct Running<'a>(&'a AtomicBool);

impl<'a> Running<'a> {
    fn start(flag: &'a AtomicBool, what: &str) -> CmdResult<Self> {
        flag.compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| Self(flag))
            .map_err(|_| format!("{what} is already running"))
    }
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        self.0.store(false, Ordering::SeqCst);
    }
}

/// First run: download Python, the speech engine's packages (plus the chosen
/// packs) and its models. Progress goes out as "engine-setup" events.
#[tauri::command]
async fn engine_install(app: AppHandle, st: State<'_, Shared>, packs: engine_setup::Packs) -> CmdResult<()> {
    let _running = Running::start(&st.installing, "Setup")?;
    let engine_dir = st.engine.script_dir();
    let http = downloads::client();
    let (app2, st2) = (app.clone(), st.inner().clone());
    let result = engine_setup::install(&http, &engine_dir, packs, move |step, pct, detail| {
        let p = system::SetupProgress { step: step.into(), pct, detail: detail.into() };
        let _ = app2.emit("engine-setup", &p);
        *st2.install_progress.lock().unwrap() = Some(p);
    })
    .await;
    *st.install_progress.lock().unwrap() = None;
    result.map_err(err)?;
    warm_up_engine(app, st.inner().clone());
    Ok(())
}

/// Search recordings, meetings and tasks.
#[tauri::command]
async fn search_all(st: State<'_, Shared>, query: String) -> CmdResult<Vec<search::Hit>> {
    let st = st.inner().clone();
    tauri::async_runtime::spawn_blocking(move || search::search(&st.db, &query)).await.map_err(err)?.map_err(err)
}

/// Fix a Listen recording's text (misheard words). `words`: re-timed words for playback.
#[tauri::command]
fn update_dictation_text(st: State<Shared>, id: i64, text: String, words: Value) -> CmdResult<()> {
    st.db.update_dictation_text(id, text.trim(), &words).map_err(err)
}

#[tauri::command]
fn delete_dictation(st: State<Shared>, id: i64) -> CmdResult<()> {
    if let Some(audio) = st.db.delete_dictation(id).map_err(err)? {
        let _ = std::fs::remove_file(audio);
    }
    Ok(())
}

/// The recording of a listening session, as bytes for the History player
/// (read off the main thread: an hour is ~100 MB as WAV).
#[tauri::command]
async fn dictation_audio(st: State<'_, Shared>, id: i64) -> CmdResult<tauri::ipc::Response> {
    let path = st.db.dictation_audio_path(id).map_err(err)?.ok_or("This entry has no recording")?;
    let bytes = tauri::async_runtime::spawn_blocking(move || std::fs::read(&path))
        .await
        .map_err(err)?
        .map_err(|e| format!("Recording not found: {e}"))?;
    Ok(tauri::ipc::Response::new(bytes))
}

#[derive(Serialize)]
struct Levels {
    listening: Option<f32>,
    mic: Option<f32>,
    system: Option<f32>,
    enroll: Option<f32>,
}

/// Polled by the meters many times a second on the main thread: never waits for
/// a lock (one that's busy, e.g. while a device opens, reads as no level).
#[tauri::command]
fn audio_levels(st: State<Shared>) -> Levels {
    let listening = st.session.try_lock().ok().and_then(|g| g.as_ref().and_then(|s| s.mic_level()));
    let enroll = st.enroll.try_lock().ok().and_then(|g| g.as_ref().map(|r| r.level()));
    let (mic, system) = match st.meeting.try_lock() {
        Ok(m) => (m.as_ref().map(|m| m.mic.level()), m.as_ref().and_then(|m| m.system.as_ref().map(|s| s.level()))),
        Err(_) => (None, None),
    };
    Levels { listening, mic, system, enroll }
}

// --------------------------------------------------------------------------- //
// Setup
// --------------------------------------------------------------------------- //

/// The speech engine: Python + engine/engine.py.
/// - Development (`tauri dev`, a debug build): the project's `.venv` and
///   `engine/` (when they exist).
/// - Release builds, always: Python set up on first run (engine_setup.rs) and
///   the engine files that ship with the app. Even on the computer that built
///   it, so testing the installer there is what a friend gets.
///
/// VOICEDESK_PYTHON / VOICEDESK_ENGINE override either.
fn engine_paths(resources: Option<PathBuf>) -> (PathBuf, PathBuf) {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().to_path_buf();
    // venv layout differs: Scripts\python.exe on Windows, bin/python on macOS/Linux.
    let venv_python = if cfg!(windows) {
        root.join(".venv").join("Scripts").join("python.exe")
    } else {
        root.join(".venv").join("bin").join("python")
    };
    let dev = cfg!(debug_assertions) && venv_python.exists() && root.join("engine").join("engine.py").exists();
    let python = std::env::var_os("VOICEDESK_PYTHON").map(PathBuf::from).unwrap_or_else(|| {
        if dev {
            venv_python
        } else {
            engine_setup::python_exe()
        }
    });
    let script = std::env::var_os("VOICEDESK_ENGINE").map(PathBuf::from).unwrap_or_else(|| {
        let bundled = resources.map(|r| r.join("engine").join("engine.py"));
        match bundled {
            Some(b) if !dev && b.exists() => b,
            _ => root.join("engine").join("engine.py"),
        }
    });
    (python, script)
}

pub(crate) fn warm_up_engine(app: AppHandle, st: Shared) {
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
        // The same options as listening and meetings, so the first one doesn't load Whisper again.
        let mut args = json!({ "model": s.whisper_model, "device": s.device });
        session::merge_json(&mut args, s.language_options());
        let res = st.engine.request("load", args, None).await;
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
    if settings.device == "cpu" {
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

/// Recordings from before compression existed (and any left by a crash): turn
/// them into FLAC once, in the background, and update history entries.
fn compress_old_recordings(st: Shared) {
    let wavs: Vec<PathBuf> = std::fs::read_dir(st.recordings_dir())
        .map(|d| d.flatten().map(|e| e.path()).filter(|p| p.extension().is_some_and(|e| e == "wav")).collect())
        .unwrap_or_default();
    if wavs.is_empty() {
        return;
    }
    tauri::async_runtime::spawn(async move {
        // Never touch a file that's being recorded right now.
        let busy: Vec<PathBuf> = {
            let mut b = Vec::new();
            if let Some(m) = st.meeting.lock().unwrap().as_ref() {
                let (mic, sys) = st.meeting_paths(m.id);
                b.extend([mic, sys]);
            }
            b
        };
        let todo: Vec<&PathBuf> = wavs.iter().filter(|p| !busy.contains(p)).collect();
        if let Ok(r) = st.engine.request("compress", json!({ "paths": todo }), None).await {
            for (from, to) in r["done"].as_object().into_iter().flatten() {
                if let Some(to) = to.as_str() {
                    let _ = st.db.rename_dictation_audio(from, to);
                }
            }
        }
    });
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
        Some("download") => on_model_download(app, &st, ev),
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

/// The engine is downloading a model (first use of a Whisper size, the
/// Hindi/Gujarati model...): passed on as "model-download", and shown as the
/// engine's status until it's done.
fn on_model_download(app: &AppHandle, st: &AppState, ev: &Value) {
    let _ = app.emit("model-download", ev);
    let what = ev["what"].as_str().unwrap_or("a model");
    let done = ev["done_mb"].as_f64().unwrap_or(0.0);
    let total = ev["total_mb"].as_f64().filter(|t| *t > 0.0);
    if total.is_some_and(|t| done >= t) {
        // Finished: back to what it was (the engine's next ready/loading event follows).
        let before = st.status_before_download.lock().unwrap().take();
        if let Some(before) = before {
            set_engine_status(app, st, before);
        }
        return;
    }
    let message = match total {
        Some(t) => format!("Downloading {what}… {:.0}%", done / t * 100.0),
        None => format!("Downloading {what}… {done:.0} MB"),
    };
    let current = st.engine_status.lock().unwrap().clone();
    if current["message"] == message.as_str() {
        return; // only whole-percent (or MB) changes go out
    }
    if current["state"] != "downloading" {
        *st.status_before_download.lock().unwrap() = Some(current);
    }
    set_engine_status(app, st, json!({ "state": "downloading", "message": message }));
}

/// Everything Voice Desk started stops with it: speech engine, task AI, recordings.
/// Recordings are finished right here (a WAV's header is written when it ends),
/// since the app exits as soon as this returns; that takes ~0.1 s per recording.
fn shutdown_services(app: &AppHandle) {
    let st = app.state::<Shared>();
    overlay::save(st.inner());
    if let Some(m) = st.meeting.lock().unwrap().take() {
        let id = m.id;
        let (mic, sys) = st.meeting_paths(id);
        let _ = m.finish(&mic, &sys);
        // Kept as it was recorded; Reprocess on the Meetings page transcribes it.
        let _ = st.db.set_meeting_status(id, "error", Some("Voice Desk was closed during the recording. Use Reprocess to transcribe it."));
    }
    session::close(app, st.inner());
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
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .setup(|app| {
            let data_dir = app.path().app_data_dir()?;
            let recordings_dir = data_dir.join("recordings");
            std::fs::create_dir_all(&recordings_dir)?;
            let db = Db::open(&data_dir.join("voicedesk.db"))?;
            let settings = db.settings()?;
            // Moves a token saved before the credential store was used out of the database.
            let _ = db.save_settings(&settings);
            create_windows(app, &settings)?;
            if settings.keep_audio_days > 0 {
                for old in db.expire_dictation_audio(settings.keep_audio_days).unwrap_or_default() {
                    audio::remove_recording(std::path::Path::new(&old));
                }
                // Meetings keep their transcript, summary and tasks; only the audio goes.
                for id in db.meetings_older_than(settings.keep_audio_days).unwrap_or_default() {
                    for track in ["mic", "system"] {
                        audio::remove_recording(&recordings_dir.join(format!("meeting-{id}-{track}.wav")));
                    }
                }
            }
            let resources = app.path().resource_dir().ok();
            let redist = resources.as_ref().map(|r| r.join("redist"));
            let (python, script) = engine_paths(resources);
            let (work_tx, work_rx) = std::sync::mpsc::channel();

            let state: Shared = Arc::new(AppState {
                db,
                engine: Arc::new(Engine::new(python, script)),
                llm: Llm::new(redist),
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
                call_switch_at: Mutex::new(None),
                stop_armed: Mutex::new(None),
                enroll: Mutex::new(None),
                overlay_pos: Mutex::new(None),
                engine_status: Mutex::new(json!({ "state": "loading" })),
                status_before_download: Mutex::new(None),
                installing: AtomicBool::new(false),
                pulling: AtomicBool::new(false),
                install_progress: Mutex::new(None),
                models_in_use: Mutex::new(None),
            });
            app.manage(state.clone());

            let handle = app.handle().clone();
            state.engine.on_global_event(move |ev| on_engine_event(&handle, ev));
            let (handle, st) = (app.handle().clone(), state.clone());
            std::thread::Builder::new()
                .name("session-worker".into())
                .spawn(move || session::worker(handle, st, work_rx))?;
            meeting_detect::watch(app.handle().clone(), state.clone());

            if let Err(e) = hotkey::register_hotkey(app.handle(), &settings) {
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
            compress_old_recordings(state.clone());
            // The task AI starts only while finding tasks (and stops a minute later).
            drop(state);

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
                        let (app, st) = (app.clone(), app.state::<Shared>().inner().clone());
                        session::in_order(move || {
                            if let Err(e) = session::toggle(&app, &st) {
                                let _ = app.emit("session-notice", json!({ "message": e }));
                            }
                        });
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
            system::data_paths,
            system::open_folder,
            audio_levels,
            meetings::start_meeting,
            meetings::stop_meeting,
            meetings::active_meeting,
            meetings::reprocess_meeting,
            meetings::list_meetings,
            meetings::get_transcript,
            meetings::meeting_audio,
            meetings::meeting_tracks,
            meetings::dictation_find_tasks,
            meetings::rename_meeting,
            meetings::delete_meeting,
            meetings::rename_speaker,
            meetings::update_transcript_line,
            update_dictation_text,
            search_all,
            engine_install,
            meetings::call_prompt_accept,
            meetings::call_prompt_dismiss,
            system::watched_call_apps,
            system::hardware_info,
            system::resource_usage,
            system::models_info,
            system::delete_model,
            meetings::dictation_to_meeting,
            meetings::meeting_to_dictation,
            tasks::list_tasks,
            tasks::set_task_done,
            tasks::update_task,
            tasks::add_task,
            tasks::delete_task,
            tasks::reorder_tasks,
            voice::voice_profile_info,
            voice::enroll_start,
            voice::enroll_stop,
            voice::delete_voice_profile,
            system::setup_status,
            system::llm_pull,
            system::engine_state,
            system::engine_restart,
            system::overlay_resize,
        ])
        .build(tauri::generate_context!())
        .expect("error while building Voice Desk")
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                shutdown_services(app);
            }
        });
}

#[cfg(test)]
mod tests {
    /// The installer ships the engine's runtime modules, listed one by one in
    /// tauri.conf.json (resources can't exclude files): tests and benchmarks stay
    /// out, and a new module must not be forgotten.
    #[test]
    fn bundle_lists_every_engine_module() {
        let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let conf: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(root.join("tauri.conf.json")).unwrap()).unwrap();
        let resources = conf["bundle"]["resources"].as_object().unwrap();
        for e in std::fs::read_dir(root.join("../engine")).unwrap().flatten() {
            let name = e.file_name().to_string_lossy().to_string();
            if !name.ends_with(".py") {
                continue;
            }
            let listed = resources.contains_key(&format!("../engine/{name}"));
            let runtime = !name.starts_with("test_") && !name.starts_with("bench_");
            assert_eq!(listed, runtime, "{name}: listed in the bundle = {listed}");
        }
        assert!(!resources.keys().any(|k| k.contains('*') && k.ends_with(".py")));
    }
}
