//! Voice Desk's backend, with no desktop code: the speech engine client and
//! setup, turning recordings into transcripts and tasks, the task AI, the
//! database, search and downloaded models. The desktop app (desktop/backend/app)
//! records audio and calls into this; a server could do the same.

pub mod catalog;
pub mod db;
pub mod downloads;
pub mod engine;
pub mod engine_setup;
pub mod hardware;
pub mod llm;
pub mod models;
pub mod omit;
pub mod paths;
pub mod pipeline;
pub mod recordings;
pub mod rules;
pub mod search;
pub mod setup;
pub mod transcript;
mod secrets;

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde_json::Value;

use db::Db;
use engine::Engine;
use llm::Llm;

pub fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}

/// Add `extra`'s fields to `target` (both JSON objects).
pub fn merge_json(target: &mut Value, extra: Value) {
    if let (Some(t), Value::Object(e)) = (target.as_object_mut(), extra) {
        t.extend(e);
    }
}

/// Where the backend's progress and change notices go ("meeting-progress",
/// "meetings-changed", "tasks-changed"...): the desktop app's windows, or a
/// server's clients.
pub trait Events: Send + Sync {
    fn emit(&self, event: &str, payload: Value);
}

/// The backend's state: one per app (or server).
pub struct Backend {
    pub db: Db,
    pub engine: Arc<Engine>,
    pub llm: Llm,
    pub data_dir: PathBuf,
    pub recordings_dir: PathBuf,
    pub events: Arc<dyn Events>,
    /// The engine's last "models_in_use" answer and the settings it was for, so
    /// listing models doesn't wake a sleeping engine to ask again.
    pub models_in_use: Mutex<Option<(String, Value)>>,
}

impl Backend {
    pub fn new(db: Db, engine: Engine, llm: Llm, data_dir: PathBuf, recordings_dir: PathBuf, events: Arc<dyn Events>) -> Self {
        Self { db, engine: Arc::new(engine), llm, data_dir, recordings_dir, events, models_in_use: Mutex::new(None) }
    }

    pub fn emit(&self, event: &str, payload: Value) {
        self.events.emit(event, payload);
    }

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
