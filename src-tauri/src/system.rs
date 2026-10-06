//! Setup status, folders, the speech engine, hardware and the overlay window.

use std::path::PathBuf;
use std::sync::atomic::Ordering;

use serde::Serialize;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter, State};

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
pub fn watched_call_apps() -> &'static str {
    meeting_detect::WATCHED
}

/// Where engine setup is ("engine-setup" events carry the same).
#[derive(Serialize, Clone)]
pub struct SetupProgress {
    pub step: String,
    pub pct: f64,
    pub detail: String,
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

#[tauri::command]
pub async fn llm_pull(app: AppHandle, st: State<'_, Shared>) -> CmdResult<()> {
    let _running = crate::Running::start(&st.pulling, "The task AI download")?;
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
pub struct DataPaths {
    pub app_data: PathBuf,
    pub database: PathBuf,
    pub recordings: PathBuf,
    pub voice_profile: PathBuf,
    pub speech_models: PathBuf,
    pub llm_models: PathBuf,
}

pub(crate) fn home_dir() -> PathBuf {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(PathBuf::from).unwrap_or_default()
}

#[tauri::command]
pub fn data_paths(st: State<Shared>) -> DataPaths {
    let hf = std::env::var_os("HF_HOME")
        .map(|h| PathBuf::from(h).join("hub"))
        .unwrap_or_else(|| home_dir().join(".cache").join("huggingface").join("hub"));

    DataPaths {
        app_data: st.data_dir.clone(),
        database: st.data_dir.join("voicedesk.db"),
        recordings: st.recordings_dir.clone(),
        voice_profile: st.voice_profile_path(),
        speech_models: hf,
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

#[derive(Serialize)]
pub struct ModelInfo {
    /// Folder or file name, used to delete it.
    pub id: String,
    pub name: String,
    pub size_gb: f64,
    /// The current settings use it (or might, as a fallback): not deletable.
    pub in_use: bool,
}

/// Where Voice Desk keeps the models it downloads itself (speaker detection,
/// the small Hindi/Gujarati encoder). Same as the engine's `models_dir()`.
pub(crate) fn voicedesk_models_dir() -> PathBuf {
    if cfg!(windows) {
        std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(home_dir).join("VoiceDesk").join("models")
    } else if cfg!(target_os = "macos") {
        home_dir().join("Library/Caches/VoiceDesk/models")
    } else {
        std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|| home_dir().join(".cache")).join("voicedesk/models")
    }
}

fn size_of(path: &std::path::Path) -> u64 {
    match std::fs::metadata(path) {
        Ok(m) if m.is_file() => m.len(),
        Ok(_) => std::fs::read_dir(path).map(|d| d.flatten().map(|e| size_of(&e.path())).sum()).unwrap_or(0),
        Err(_) => 0,
    }
}

/// A Hugging Face cache folder -> (what it is, Whisper size if it's a Whisper model).
fn hf_model(folder: &str) -> Option<(String, Option<String>)> {
    let repo = folder.strip_prefix("models--")?.replace("--", "/");
    if let Some(size) = repo.rsplit('/').next().and_then(|n| n.strip_prefix("faster-whisper-")) {
        return Some((format!("Speech model: Whisper {size}"), Some(size.to_string())));
    }
    let name = match repo.as_str() {
        r if r.starts_with("ai4bharat/") => "Hindi/Gujarati model (support files)",
        r if r.starts_with("Wespeaker/") => "Voice ID",
        r if r.starts_with("pyannote/") => "Old speaker detection (no longer used)",
        _ => return Some((format!("Other: {repo}"), None)),
    };
    Some((name.to_string(), None))
}

#[tauri::command]
pub async fn models_info(st: State<'_, Shared>) -> CmdResult<Vec<ModelInfo>> {
    let s = st.db.settings().map_err(err)?;
    let mut args = json!({ "model": s.whisper_model, "device": s.device });
    crate::session::merge_json(&mut args, s.language_options());
    // Asked only if the engine is running (waking it costs ~0.5-1 GB); otherwise
    // its last answer for these settings. If it can't say, nothing Whisper is
    // offered for deletion.
    let key = args.to_string();
    let used = match st.engine.request_if_running("models_in_use", args).await {
        Ok(u) => {
            *st.models_in_use.lock().unwrap() = Some((key, u.clone()));
            Some(u)
        }
        Err(_) => st.models_in_use.lock().unwrap().as_ref().filter(|(k, _)| *k == key).map(|(_, u)| u.clone()),
    };
    let whisper_used =
        |size: &str| used.as_ref().is_none_or(|u| u["whisper"].as_array().is_some_and(|a| a.iter().any(|x| x == size)));
    let indic_used = used.as_ref().is_none_or(|u| u["indic"].as_bool().unwrap_or(true));

    let mut out = Vec::new();
    let hub = data_paths(st.clone()).speech_models;
    for e in std::fs::read_dir(&hub).into_iter().flatten().flatten() {
        let folder = e.file_name().to_string_lossy().to_string();
        let Some((name, whisper)) = hf_model(&folder) else { continue };
        let in_use = match &whisper {
            Some(size) => whisper_used(size),
            None if folder.contains("ai4bharat") => indic_used,
            None => !folder.contains("pyannote"),
        };
        out.push(ModelInfo { id: format!("hf:{folder}"), name, size_gb: size_of(&e.path()) as f64 / 1e9, in_use });
    }
    for e in std::fs::read_dir(voicedesk_models_dir()).into_iter().flatten().flatten() {
        let file = e.file_name().to_string_lossy().to_string();
        let task_model = crate::llm::task_model(&s);
        let (name, in_use) = if file.starts_with("speakers-") {
            ("Speaker detection", true)
        } else if file.ends_with(".gguf") {
            let label = if file.contains("1.7B") { "Task AI: Qwen3 1.7B" } else { "Task AI: Qwen3 4B" };
            (label, file == task_model.file())
        } else if file.starts_with("indic-encoder-int8") {
            ("Hindi/Gujarati model", indic_used)
        } else {
            continue;
        };
        out.push(ModelInfo { id: format!("vd:{file}"), name: name.into(), size_gb: size_of(&e.path()) as f64 / 1e9, in_use });
    }
    out.sort_by(|a, b| b.in_use.cmp(&a.in_use).then(b.size_gb.total_cmp(&a.size_gb)));
    Ok(out)
}

/// Delete a downloaded model the current settings don't use. It downloads again
/// by itself if a later setting needs it.
#[tauri::command]
pub async fn delete_model(st: State<'_, Shared>, id: String) -> CmdResult<()> {
    let models = models_info(st.clone()).await?;
    let m = models.iter().find(|m| m.id == id).ok_or("That model is no longer there")?;
    if m.in_use {
        return Err("Your current settings use this model".into());
    }
    let path = match id.split_once(':') {
        Some(("hf", folder)) => data_paths(st.clone()).speech_models.join(folder),
        Some(("vd", file)) => voicedesk_models_dir().join(file),
        _ => return Err("Unknown model".into()),
    };
    // Only ever inside the two model folders, and only a plain name.
    if id.contains("..") || id.contains(['/', '\\']) {
        return Err("Unknown model".into());
    }
    let res = if path.is_dir() { std::fs::remove_dir_all(&path) } else { std::fs::remove_file(&path) };
    res.map_err(|e| format!("Couldn't delete it: {e}"))
}

#[cfg(test)]
mod tests {
    use super::hf_model;

    #[test]
    fn recognises_downloaded_models() {
        assert_eq!(
            hf_model("models--Systran--faster-whisper-small"),
            Some(("Speech model: Whisper small".into(), Some("small".into())))
        );
        assert_eq!(hf_model("models--mobiuslabsgmbh--faster-whisper-large-v3-turbo").unwrap().1.as_deref(), Some("large-v3-turbo"));
        assert_eq!(hf_model("models--pyannote--speaker-diarization-community-1").unwrap().0, "Old speaker detection (no longer used)");
        assert_eq!(hf_model("CACHEDIR.TAG"), None);
    }
}
