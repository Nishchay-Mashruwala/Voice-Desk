//! The user's voice profile ("is it your voice?").

use serde::Serialize;
use serde_json::{json, Value};
use tauri::{AppHandle, State};

use crate::{err, CmdResult, Shared};
use crate::audio::{Recording, Source};

#[derive(Serialize)]
pub struct VoiceProfile {
    pub exists: bool,
    pub created_at: Option<String>,
}

#[tauri::command]
pub fn voice_profile_info(st: State<Shared>) -> VoiceProfile {
    let path = st.voice_profile_path();
    let created_at = std::fs::metadata(&path)
        .and_then(|m| m.modified())
        .ok()
        .map(|t| chrono::DateTime::<chrono::Local>::from(t).to_rfc3339());
    VoiceProfile { exists: path.exists(), created_at }
}

/// Opens the microphone on the session's thread (not the main one), so a
/// second click can't open it twice: the check and the open happen in turn.
#[tauri::command]
pub async fn enroll_start(st: State<'_, Shared>) -> CmdResult<()> {
    let st = st.inner().clone();
    crate::session::in_order_async(move || {
        if st.enroll.lock().unwrap().is_some() {
            return Ok(());
        }
        let path = st.data_dir.join("voice_enroll.wav");
        let rec = Recording::to_file(Source::Microphone, &path).map_err(|e| format!("Microphone error: {e}"))?;
        *st.enroll.lock().unwrap() = Some(rec);
        Ok(())
    })
    .await?
}

#[tauri::command]
pub async fn enroll_stop(app: AppHandle, st: State<'_, Shared>, save: bool) -> CmdResult<Value> {
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
    crate::session::emit_status(&app, st.inner());
    Ok(res)
}

#[tauri::command]
pub fn delete_voice_profile(st: State<Shared>) -> CmdResult<()> {
    let path = st.voice_profile_path();
    if path.exists() {
        std::fs::remove_file(&path).map_err(err)?;
    }
    if let Some(sid) = st.session.lock().unwrap().as_ref().map(|s| s.sid) {
        let _ = st.engine.start_request("stream_update", json!({ "sid": sid, "voice_profile": null }), None);
    }
    Ok(())
}
