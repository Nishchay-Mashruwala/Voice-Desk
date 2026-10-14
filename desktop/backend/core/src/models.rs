//! Downloaded models: what's on disk, which ones the settings use, deleting one.

use serde::Serialize;
use serde_json::json;

use crate::paths::{speech_models_dir, voicedesk_models_dir};
use crate::{err, Backend};

#[derive(Serialize)]
pub struct ModelInfo {
    /// Folder or file name, used to delete it.
    pub id: String,
    /// What it is: "speech" (a Whisper model), "task_ai", "voice_id", "speakers",
    /// "indic" (the Hindi/Gujarati model), "indic_support" (its support files),
    /// "old_speakers" (no longer used) or "other".
    pub kind: &'static str,
    /// Which one: the Whisper size, the task model's catalog id, or (for
    /// "other") the Hugging Face repo.
    pub model: Option<String>,
    pub size_gb: f64,
    /// The current settings use it (or might, as a fallback).
    pub in_use: bool,
}

/// Bytes taken by a file, or a folder and everything in it.
pub fn size_of(path: &std::path::Path) -> u64 {
    match std::fs::metadata(path) {
        Ok(m) if m.is_file() => m.len(),
        Ok(_) => std::fs::read_dir(path).map(|d| d.flatten().map(|e| size_of(&e.path())).sum()).unwrap_or(0),
        Err(_) => 0,
    }
}

/// A Hugging Face cache folder -> (kind, which model) as in `ModelInfo`.
fn hf_model(folder: &str) -> Option<(&'static str, Option<String>)> {
    let repo = folder.strip_prefix("models--")?.replace("--", "/");
    if let Some(size) = repo.rsplit('/').next().and_then(|n| n.strip_prefix("faster-whisper-")) {
        return Some(("speech", Some(size.to_string())));
    }
    Some(match repo.as_str() {
        r if r.starts_with("ai4bharat/") => ("indic_support", None),
        r if r.starts_with("Wespeaker/") => ("voice_id", None),
        r if r.starts_with("pyannote/") => ("old_speakers", None),
        _ => ("other", Some(repo)),
    })
}

/// The downloaded models, the ones in use first, then the biggest.
pub async fn list(b: &Backend) -> Result<Vec<ModelInfo>, String> {
    let s = b.db.settings().map_err(err)?;
    let mut args = json!({ "model": s.whisper_model, "device": s.device });
    crate::merge_json(&mut args, s.language_options());
    // Asked only if the engine is running (waking it costs ~0.5-1 GB); otherwise
    // its last answer for these settings. If it can't say, every Whisper model
    // counts as in use.
    let key = args.to_string();
    let used = match b.engine.request_if_running("models_in_use", args).await {
        Ok(u) => {
            *b.models_in_use.lock().unwrap() = Some((key, u.clone()));
            Some(u)
        }
        Err(_) => b.models_in_use.lock().unwrap().as_ref().filter(|(k, _)| *k == key).map(|(_, u)| u.clone()),
    };
    let whisper_used =
        |size: &str| used.as_ref().is_none_or(|u| u["whisper"].as_array().is_some_and(|a| a.iter().any(|x| x == size)));
    let indic_used = used.as_ref().is_none_or(|u| u["indic"].as_bool().unwrap_or(true));

    let mut out = Vec::new();
    for e in std::fs::read_dir(speech_models_dir()).into_iter().flatten().flatten() {
        let folder = e.file_name().to_string_lossy().to_string();
        let Some((kind, model)) = hf_model(&folder) else { continue };
        let in_use = match kind {
            "speech" => model.as_deref().is_some_and(whisper_used),
            "indic_support" => indic_used,
            "old_speakers" => false,
            _ => true,
        };
        out.push(ModelInfo { id: format!("hf:{folder}"), kind, model, size_gb: size_of(&e.path()) as f64 / 1e9, in_use });
    }
    for e in std::fs::read_dir(voicedesk_models_dir()).into_iter().flatten().flatten() {
        let file = e.file_name().to_string_lossy().to_string();
        let task_model = crate::llm::task_model(&s);
        let (kind, model, in_use) = if file.starts_with("speakers-") {
            ("speakers", None, true)
        } else if file.ends_with(".gguf") {
            let id = crate::catalog::TASK_MODELS.iter().find(|m| m.file == file).map(|m| m.id.to_string());
            ("task_ai", id, file == task_model.file())
        } else if file.starts_with("indic-encoder-int8") {
            ("indic", None, indic_used)
        } else {
            continue;
        };
        out.push(ModelInfo { id: format!("vd:{file}"), kind, model, size_gb: size_of(&e.path()) as f64 / 1e9, in_use });
    }
    out.sort_by(|a, b| b.in_use.cmp(&a.in_use).then(b.size_gb.total_cmp(&a.size_gb)));
    Ok(out)
}

/// Delete a downloaded model. One the current settings use is deleted too when
/// `can_stop_in_use` (nothing is being recorded or processed): the speech
/// engine or task AI holding it is stopped first (Windows won't delete a file
/// that's open), and it downloads again when next needed.
pub async fn delete(b: &Backend, id: &str, can_stop_in_use: bool) -> Result<(), String> {
    let models = list(b).await?;
    let m = models.iter().find(|m| m.id == id).ok_or("That model is no longer there")?;
    if m.in_use {
        if !can_stop_in_use {
            return Err("It's in use right now — try again when the recording has finished".into());
        }
        if m.kind == "task_ai" {
            b.llm.shutdown();
        } else {
            b.engine.shutdown();
            *b.models_in_use.lock().unwrap() = None;
        }
    }
    let path = match id.split_once(':') {
        Some(("hf", folder)) => speech_models_dir().join(folder),
        Some(("vd", file)) => voicedesk_models_dir().join(file),
        _ => return Err("Unknown model".into()),
    };
    // Only ever inside the two model folders, and only a plain name.
    if id.contains("..") || id.contains(['/', '\\']) {
        return Err("Unknown model".into());
    }
    let remove = || if path.is_dir() { std::fs::remove_dir_all(&path) } else { std::fs::remove_file(&path) };
    let mut res = remove();
    // A process just stopped lets go of its files a moment later.
    for _ in 0..10 {
        if res.is_ok() || !m.in_use {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(300)).await;
        res = remove();
    }
    res.map_err(|e| format!("Couldn't delete it: {e}"))
}

#[cfg(test)]
mod tests {
    use super::hf_model;

    #[test]
    fn recognises_downloaded_models() {
        assert_eq!(hf_model("models--Systran--faster-whisper-small"), Some(("speech", Some("small".into()))));
        assert_eq!(hf_model("models--mobiuslabsgmbh--faster-whisper-large-v3-turbo").unwrap().1.as_deref(), Some("large-v3-turbo"));
        assert_eq!(hf_model("models--pyannote--speaker-diarization-community-1").unwrap().0, "old_speakers");
        assert_eq!(hf_model("models--someone--thing"), Some(("other", Some("someone/thing".into()))));
        assert_eq!(hf_model("CACHEDIR.TAG"), None);
    }
}
