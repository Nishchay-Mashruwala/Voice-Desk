//! Setup status, folders, the speech engine, hardware and the overlay window.

use std::path::PathBuf;
use std::sync::atomic::Ordering;

use serde::Serialize;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, State};

use voicedesk_core::catalog::{self, ModelOptions};
use voicedesk_core::models::{self, size_of, ModelInfo};
use voicedesk_core::setup;
use voicedesk_core::paths::{speech_models_dir, voicedesk_models_dir};

use crate::{err, CmdResult, Shared};
use crate::llm::LlmStatus;
use crate::{hardware, meeting_detect, overlay, warm_up_engine};

#[tauri::command]
pub async fn hardware_info() -> hardware::Hardware {
    tauri::async_runtime::spawn_blocking(hardware::info).await.expect("hardware info")
}

#[tauri::command]
pub async fn resource_usage(st: State<'_, Shared>) -> CmdResult<hardware::Usage> {
    let (engine, task_ai) = (st.engine.pid(), st.llm.pid());
    tauri::async_runtime::spawn_blocking(move || hardware::usage(engine, task_ai)).await.map_err(err)
}

#[tauri::command]
pub fn watched_call_apps() -> Value {
    json!({ "apps": meeting_detect::WATCHED, "browsers": true, "needs_pactl": meeting_detect::NEEDS_PACTL })
}

/// Where engine setup is ("engine-setup" events carry the same).
#[derive(Serialize, Clone)]
pub struct SetupProgress {
    /// "python", "engine", "nvidia", "indic", "models" or "done".
    pub step: String,
    pub pct: f64,
    /// What's being fetched ({"package"}, {"installing"}, {"model", "pct" | "mb"}, {"text"}), or null.
    pub detail: Value,
}

#[derive(Serialize)]
pub struct SetupStatus {
    pub engine_installed: bool,
    /// The engine's Python and packages are already here, setup just didn't
    /// finish: finishing it downloads only what's missing.
    pub engine_partial: bool,
    /// Optional packs of the first-run engine (None: not set up, or a development .venv).
    pub engine_packs: Option<crate::engine_setup::Packs>,
    pub engine: Value,
    pub name_set: bool,
    pub hf_token_set: bool,
    pub voice_profile: bool,
    pub llm: LlmStatus,
    /// Speech engine setup (engine_install) is running.
    pub installing: bool,
    /// The task AI download (llm_pull) is running.
    pub pulling: bool,
    /// The last setup progress while `installing` (None when idle).
    pub install_progress: Option<SetupProgress>,
}

#[tauri::command]
pub async fn setup_status(st: State<'_, Shared>) -> CmdResult<SetupStatus> {
    let s = st.db.settings().map_err(err)?;
    let engine = st.engine_status.lock().unwrap().clone();
    Ok(SetupStatus {
        engine_installed: st.engine.is_installed(),
        engine_partial: st.engine.is_partly_installed(),
        engine_packs: st.engine.packs(),
        engine,
        name_set: !s.user_name.trim().is_empty(),
        hf_token_set: !s.hf_token.trim().is_empty(),
        voice_profile: st.voice_profile_path().exists(),
        llm: st.llm.status(&s),
        installing: st.installing.load(Ordering::SeqCst),
        pulling: st.pulling.load(Ordering::SeqCst),
        install_progress: st.install_progress.lock().unwrap().clone(),
    })
}

/// Download the task AI the settings use. Progress goes out as "llm-pull"
/// events: {step: "runtime" | "model" | "done", pct, model}.
pub(crate) async fn pull_task_ai(app: &AppHandle, st: &Shared) -> CmdResult<()> {
    let _running = crate::Running::start(&st.pulling, "The task AI download")?;
    let s = st.db.settings().map_err(err)?;
    let model = crate::llm::task_model(&s).id();
    let mut last = -10.0;
    st.llm
        .pull(&s, |step, pct| {
            // Whole-percent steps are enough (and far fewer messages).
            if pct < 0.0 || pct - last >= 1.0 || pct >= 100.0 {
                last = pct;
                let _ = app.emit("llm-pull", json!({ "step": step, "pct": pct, "model": model }));
            }
        })
        .await
        .map_err(err)
}

/// The models Settings offers for the settings on screen (`draft`, maybe not saved).
#[tauri::command]
pub async fn model_options(st: State<'_, Shared>, draft: crate::db::Settings) -> CmdResult<ModelOptions> {
    // Whisper uses an NVIDIA GPU only with the NVIDIA pack (a development .venv has what it has).
    let nvidia_ready = st.engine.packs().map_or(true, |p| p.nvidia);
    let hw = tauri::async_runtime::spawn_blocking(hardware::info).await.map_err(err)?;
    Ok(catalog::model_options(&draft, &hw, nvidia_ready))
}

/// What first-run setup would download for the settings on screen (`draft`).
#[tauri::command]
pub async fn setup_plan(st: State<'_, Shared>, draft: crate::db::Settings, choices: setup::Choices) -> CmdResult<setup::SetupPlan> {
    let gpus = tauri::async_runtime::spawn_blocking(hardware::gpus).await.map_err(err)?;
    Ok(setup::plan_for(&st, &draft, choices, setup::big_gpu(&gpus)))
}

#[derive(Serialize)]
pub struct DataPaths {
    pub app_data: PathBuf,
    pub database: PathBuf,
    pub recordings: PathBuf,
    pub voice_profile: PathBuf,
    pub speech_models: PathBuf,
    pub llm_models: PathBuf,
}

#[tauri::command]
pub fn data_paths(st: State<Shared>) -> DataPaths {
    DataPaths {
        app_data: st.data_dir.clone(),
        database: st.data_dir.join("voicedesk.db"),
        recordings: st.recordings_dir.clone(),
        voice_profile: st.voice_profile_path(),
        speech_models: speech_models_dir(),
        llm_models: voicedesk_models_dir(),
    }
}

#[tauri::command]
pub fn open_folder(app: AppHandle, path: String) -> CmdResult<()> {
    use tauri_plugin_opener::OpenerExt;
    app.opener().open_path(path, None::<&str>).map_err(err)
}

#[tauri::command]
pub fn overlay_resize(app: AppHandle, width: f64, height: f64) {
    overlay::resize(&app, width, height);
}

#[tauri::command]
pub fn engine_state(st: State<Shared>) -> Value {
    st.engine_status.lock().unwrap().clone()
}

#[tauri::command]
pub fn engine_restart(app: AppHandle, st: State<Shared>) {
    st.engine.shutdown();
    warm_up_engine(app, st.inner().clone());
}

// --------------------------------------------------------------------------- //
// Downloaded models (Settings -> Storage)
// --------------------------------------------------------------------------- //

#[tauri::command]
pub async fn models_info(st: State<'_, Shared>) -> CmdResult<Vec<ModelInfo>> {
    models::list(&st).await
}

/// Disk space Voice Desk takes (Settings -> Storage), in GB.
#[derive(Serialize)]
pub struct DiskUsage {
    /// The installed program.
    pub app_gb: f64,
    /// The speech engine's Python and packages, and the task AI's runner.
    pub engines_gb: f64,
    /// Downloaded models (the "Downloaded models" list).
    pub models_gb: f64,
    /// Database, recordings, voice profile.
    pub data_gb: f64,
}

/// The installed program's size: the .app on a Mac, the AppImage, or the
/// program and its resources (in development only the program file).
fn app_size(app: &AppHandle) -> u64 {
    use tauri::Manager;
    let Ok(exe) = std::env::current_exe() else { return 0 };
    if cfg!(debug_assertions) {
        return size_of(&exe);
    }
    if let Some(bundle) = exe.ancestors().find(|p| p.extension().is_some_and(|e| e == "app")) {
        return size_of(bundle);
    }
    if let Some(image) = std::env::var_os("APPIMAGE") {
        return size_of(std::path::Path::new(&image));
    }
    let Some(exe_dir) = exe.parent() else { return size_of(&exe) };
    match app.path().resource_dir() {
        // Linux packages: the program in /usr/bin, its resources in /usr/lib/<app>.
        Ok(res) if !res.starts_with(exe_dir) => size_of(&exe) + size_of(&res),
        // Windows: the install folder holds both.
        _ => size_of(exe_dir),
    }
}

#[tauri::command]
pub async fn disk_usage(app: AppHandle, st: State<'_, Shared>) -> CmdResult<DiskUsage> {
    let models_gb = models::list(&st).await?.iter().map(|m| m.size_gb).sum();
    let data_dir = st.data_dir.clone();
    // Thousands of files (the engine's packages): off the async threads.
    let (app_bytes, engines, data) = tauri::async_runtime::spawn_blocking(move || {
        let base = crate::downloads::base_dir();
        (app_size(&app), size_of(&base.join("runtime")) + size_of(&base.join("llama")), size_of(&data_dir))
    })
    .await
    .map_err(err)?;
    Ok(DiskUsage { app_gb: app_bytes as f64 / 1e9, engines_gb: engines as f64 / 1e9, models_gb, data_gb: data as f64 / 1e9 })
}

/// Delete a downloaded model, also one the current settings use while nothing
/// is being recorded or processed.
#[tauri::command]
pub async fn delete_model(st: State<'_, Shared>, id: String) -> CmdResult<()> {
    let busy = st.session.lock().unwrap().is_some()
        || st.meeting.lock().unwrap().is_some()
        || st.processing.load(Ordering::Relaxed) > 0
        || st.pulling.load(Ordering::Relaxed);
    models::delete(&st, &id, !busy).await
}
