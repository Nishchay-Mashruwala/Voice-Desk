//! Folders outside the app's data folder: downloaded models and runtimes.

use std::path::PathBuf;

pub fn home_dir() -> PathBuf {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" }).map(PathBuf::from).unwrap_or_default()
}

/// Where Voice Desk keeps the models it downloads itself (speaker detection,
/// the small Hindi/Gujarati encoder). Same as the engine's `models_dir()`.
pub fn voicedesk_models_dir() -> PathBuf {
    if cfg!(windows) {
        std::env::var_os("LOCALAPPDATA").map(PathBuf::from).unwrap_or_else(home_dir).join("VoiceDesk").join("models")
    } else if cfg!(target_os = "macos") {
        home_dir().join("Library/Caches/VoiceDesk/models")
    } else {
        std::env::var_os("XDG_CACHE_HOME").map(PathBuf::from).unwrap_or_else(|| home_dir().join(".cache")).join("voicedesk/models")
    }
}

/// The Hugging Face cache, where the speech models (Whisper...) are downloaded.
pub fn speech_models_dir() -> PathBuf {
    std::env::var_os("HF_HOME")
        .map(|h| PathBuf::from(h).join("hub"))
        .unwrap_or_else(|| home_dir().join(".cache").join("huggingface").join("hub"))
}
