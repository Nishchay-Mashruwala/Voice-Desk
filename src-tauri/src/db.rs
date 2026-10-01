//! SQLite persistence: settings, dictation history, meetings, and tasks.

use std::path::Path;
use std::sync::Mutex;

use anyhow::Result;
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Your name, as other people say it in meetings.
    pub user_name: String,
    /// Other names/nicknames people use for you (comma separated).
    pub aliases: String,
    pub dictation_hotkey: String,
    /// How the shortcut starts/stops listening: "toggle" (press once), "double"
    /// (double-press), "long" (hold for `long_press_s`), or "hold" (push-to-talk).
    pub dictation_mode: String,
    pub long_press_s: f32,
    /// "paste" (clipboard + Ctrl+V, fast) or "type" (simulated keystrokes, slower but clipboard-free).
    pub insert_method: String,
    /// How long a pause (ms) ends a phrase and sends it to be typed.
    pub silence_ms: u32,

    /// The name that must be said before a voice command ("Jarvis, pause").
    pub assistant_name: String,
    /// Phrases for each command, comma separated alternatives.
    pub cmd_stop: String,
    pub cmd_pause: String,
    pub cmd_resume: String,
    pub cmd_record_tasks: String,
    pub cmd_tasks_recorded: String,
    /// With a voice profile: only the user's voice can give commands.
    pub voice_lock: bool,
    /// With a voice profile: only type speech in the user's voice.
    pub only_my_voice: bool,

    /// ISO code like "en"; empty = auto-detect. Superseded by `languages`.
    pub language: String,
    /// Languages the user speaks, e.g. ["en", "hi", "gu"]. Each phrase is
    /// detected among these.
    pub languages: Vec<String>,
    /// When both Hindi and Gujarati are chosen: which one to write. (Whisper
    /// can tell English from Indian languages, but not Hindi from Gujarati.)
    pub prefer_indic: String,
    /// "none" | "gujarati" | "all": which languages are translated to English.
    pub translate: String,
    /// "auto" picks by hardware and languages (see the engine's `_candidates`).
    pub whisper_model: String,
    /// "auto" | "cuda" | "cpu"
    pub whisper_device: String,
    /// Words Whisper should spell correctly (names, jargon).
    pub vocabulary: String,
    /// Free the speech engine's memory after this many idle minutes (0 = never).
    pub unload_after_min: u32,
    /// Delete dictation recordings (not their text) after this many days (0 = keep forever).
    pub keep_audio_days: u32,
    /// Closing the window keeps Voice Desk running in the tray (otherwise it quits).
    pub close_to_tray: bool,
    /// Offer to transcribe when a call app (Zoom, Meet in a browser...) starts using the mic.
    pub detect_meetings: bool,
    /// Opening a task's source starts playback this many seconds before the task was said.
    pub task_jump_lead_s: u32,

    pub hf_token: String,
    pub ollama_url: String,
    pub llm_model: String,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            user_name: String::new(),
            aliases: String::new(),
            dictation_hotkey: "Ctrl+Shift+Space".into(),
            dictation_mode: "toggle".into(),
            long_press_s: 5.0,
            insert_method: "paste".into(),
            silence_ms: 700,
            assistant_name: "Jarvis".into(),
            cmd_stop: "stop, stop listening".into(),
            cmd_pause: "pause".into(),
            cmd_resume: "resume".into(),
            cmd_record_tasks: "record task, record tasks".into(),
            cmd_tasks_recorded: "task recorded, tasks recorded".into(),
            voice_lock: true,
            only_my_voice: false,
            language: "en".into(),
            languages: Vec::new(),
            prefer_indic: "gu".into(),
            translate: "gujarati".into(),
            whisper_model: "auto".into(),
            whisper_device: "auto".into(),
            vocabulary: String::new(),
            unload_after_min: 10,
            keep_audio_days: 30,
            close_to_tray: false,
            detect_meetings: true,
            task_jump_lead_s: 5,
            hf_token: String::new(),
            ollama_url: "http://127.0.0.1:11434".into(),
            llm_model: "qwen3:4b".into(),
        }
    }
}

impl Settings {
    /// Command id -> phrases, as the engine expects.
    pub fn commands(&self) -> serde_json::Value {
        serde_json::json!({
            "stop": self.cmd_stop,
            "pause": self.cmd_pause,
            "resume": self.cmd_resume,
            "record_tasks": self.cmd_record_tasks,
            "tasks_recorded": self.cmd_tasks_recorded,
        })
    }

    /// The languages to recognise (older settings only had one `language`).
    pub fn langs(&self) -> Vec<String> {
        if !self.languages.is_empty() {
            return self.languages.clone();
        }
        let one = self.language.trim();
        vec![if one.is_empty() { "en".to_string() } else { one.to_string() }]
    }

    /// Engine language options, shared by live dictation and meetings.
    pub fn language_options(&self) -> serde_json::Value {
        let translate = match self.translate.as_str() {
            "all" => serde_json::json!(true),
            "gujarati" => serde_json::json!(["gu"]),
            _ => serde_json::json!(false),
        };
        serde_json::json!({
            "languages": self.langs(),
            "prefer": self.prefer_indic,
            "translate": translate,
        })
    }

    /// Names and words Whisper should get right, fed to it as a prompt.
    pub fn whisper_vocabulary(&self) -> String {
        let mut words: Vec<String> = Vec::new();
        let sources = [&self.assistant_name, &self.user_name, &self.aliases, &self.vocabulary];
        for w in sources.iter().flat_map(|s| s.split([',', '\n'])).map(str::trim).chain(["Voice Desk"]) {
            if !w.is_empty() && !words.iter().any(|x| x.eq_ignore_ascii_case(w)) {
                words.push(w.to_string());
            }
        }
        words.join(", ")
    }
}

#[derive(Debug, Clone, Serialize)]
pub struct Dictation {
    pub id: i64,
    pub text: String,
    pub duration_ms: i64,
    pub created_at: String,
    pub has_audio: bool,
    /// [{"w": word, "s": start_s, "e": end_s, "st": "typed" | "paused" | ...}] for playback highlighting.
    pub words: serde_json::Value,
    /// Hidden "dictation" meeting holding this recording's tasks, once "Find tasks" ran.
    pub meeting_id: Option<i64>,
    /// Tasks found in this recording, for underlining where they were said.
    pub tasks: Vec<DictationTask>,
}

#[derive(Debug, Clone, Serialize)]
pub struct DictationTask {
    pub description: String,
    pub quote: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct Meeting {
    pub id: i64,
    pub title: String,
    /// "meeting" (recorded from the Meetings page) or "capture" ("Jarvis, record tasks")
    pub kind: String,
    pub started_at: String,
    pub ended_at: Option<String>,
    /// recording | transcribing | extracting | done | error
    pub status: String,
    pub error: Option<String>,
    pub duration_s: Option<f64>,
    pub summary: Option<String>,
    pub task_count: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Segment {
    pub start: f64,
    pub end: f64,
    pub speaker: String,
    pub text: String,
    /// Each word's timing, for playback highlighting. None in older transcripts.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub words: Option<Vec<Word>>,
}

/// A word and when it was said (s, from the start of the recording).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Word {
    pub w: String,
    pub s: f64,
    pub e: f64,
}

#[derive(Debug, Clone, Serialize)]
pub struct Task {
    pub id: i64,
    pub meeting_id: Option<i64>,
    pub meeting_title: Option<String>,
    /// The source's kind ("meeting" | "capture" | "dictation"), to open it from the task.
    pub meeting_kind: Option<String>,
    /// The Listen recording it was said in (captures and "Find tasks" runs).
    pub dictation_id: Option<i64>,
    pub description: String,
    pub assigned_by: Option<String>,
    pub due: Option<String>,
    pub quote: Option<String>,
    pub done: bool,
    pub position: i64,
    pub created_at: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct NewTask {
    pub description: String,
    pub assigned_by: Option<String>,
    pub due: Option<String>,
    pub quote: Option<String>,
}

pub struct Db(Mutex<Connection>);

fn now() -> String {
    chrono::Local::now().to_rfc3339()
}

const MIGRATIONS: &[&str] = &[
    // v1: initial schema
    r#"
    CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS dictations (
        id INTEGER PRIMARY KEY, text TEXT NOT NULL, duration_ms INTEGER NOT NULL, created_at TEXT NOT NULL
    );
    CREATE TABLE IF NOT EXISTS meetings (
        id INTEGER PRIMARY KEY, title TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
        status TEXT NOT NULL, error TEXT, duration_s REAL, summary TEXT, transcript TEXT
    );
    CREATE TABLE IF NOT EXISTS tasks (
        id INTEGER PRIMARY KEY, meeting_id INTEGER REFERENCES meetings(id) ON DELETE CASCADE,
        description TEXT NOT NULL, assigned_by TEXT, due TEXT, quote TEXT,
        done INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL
    );
    "#,
    // v2: manual task ordering (lower = higher in the list; newest first by default)
    // and task captures started by voice.
    r#"
    ALTER TABLE tasks ADD COLUMN position INTEGER NOT NULL DEFAULT 0;
    UPDATE tasks SET position = -id;
    ALTER TABLE meetings ADD COLUMN kind TEXT NOT NULL DEFAULT 'meeting';
    "#,
    // v3: each listening session keeps its recording and word timings.
    r#"
    ALTER TABLE dictations ADD COLUMN audio_path TEXT;
    ALTER TABLE dictations ADD COLUMN words TEXT;
    "#,
    // v4: "Find tasks" on a recording reuses one meeting instead of adding duplicates.
    r#"
    ALTER TABLE dictations ADD COLUMN meeting_id INTEGER;
    "#,
    // v5: voice task recordings belong to the Listen recording they were said in.
    // Existing ones: the recording whose session was running when it started.
    r#"
    ALTER TABLE meetings ADD COLUMN dictation_id INTEGER;
    UPDATE meetings SET dictation_id = (
        SELECT d.id FROM dictations d
        WHERE julianday(d.created_at) >= julianday(meetings.started_at)
          AND julianday(d.created_at) - d.duration_ms / 86400000.0 <= julianday(meetings.started_at) + 5 / 86400.0
        ORDER BY d.created_at LIMIT 1
    ) WHERE kind = 'capture';
    "#,
];

impl Db {
    pub fn open(path: &Path) -> Result<Self> {
        let mut conn = Connection::open(path)?;
        conn.execute_batch("PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;")?;
        let version = conn.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))? as usize;
        // Databases created before migrations existed already have the v1 tables.
        let has_tasks: bool = conn
            .query_row("SELECT 1 FROM sqlite_master WHERE name = 'tasks'", [], |_| Ok(true))
            .optional()?
            .unwrap_or(false);
        let start = if version == 0 && has_tasks { 1 } else { version };
        for (i, sql) in MIGRATIONS.iter().enumerate().skip(start) {
            let tx = conn.transaction()?;
            tx.execute_batch(sql)?;
            tx.pragma_update(None, "user_version", (i + 1) as i64)?;
            tx.commit()?;
        }
        // A crash mid-processing would otherwise leave meetings stuck forever.
        conn.execute(
            "UPDATE meetings SET status = 'error', error = 'Interrupted (app closed during processing)'
             WHERE status IN ('recording', 'transcribing', 'extracting')",
            [],
        )?;
        Ok(Self(Mutex::new(conn)))
    }

    // ---- settings -------------------------------------------------------

    pub fn settings(&self) -> Result<Settings> {
        Ok(self.get_value("app")?.and_then(|s| serde_json::from_str(&s).ok()).unwrap_or_default())
    }

    pub fn save_settings(&self, s: &Settings) -> Result<()> {
        self.set_value("app", &serde_json::to_string(s)?)
    }

    pub fn get_value(&self, key: &str) -> Result<Option<String>> {
        let c = self.0.lock().unwrap();
        Ok(c.query_row("SELECT value FROM settings WHERE key = ?1", [key], |r| r.get(0)).optional()?)
    }

    pub fn set_value(&self, key: &str, value: &str) -> Result<()> {
        self.0.lock().unwrap().execute(
            "INSERT INTO settings (key, value) VALUES (?1, ?2)
             ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            params![key, value],
        )?;
        Ok(())
    }

    // ---- dictations -----------------------------------------------------

    pub fn add_dictation(
        &self,
        text: &str,
        duration_ms: i64,
        audio_path: Option<&Path>,
        words: &serde_json::Value,
    ) -> Result<Dictation> {
        let c = self.0.lock().unwrap();
        let created_at = now();
        c.execute(
            "INSERT INTO dictations (text, duration_ms, created_at, audio_path, words) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![
                text,
                duration_ms,
                created_at,
                audio_path.map(|p| p.to_string_lossy().to_string()),
                words.to_string()
            ],
        )?;
        Ok(Dictation {
            id: c.last_insert_rowid(),
            text: text.into(),
            duration_ms,
            created_at,
            has_audio: audio_path.is_some(),
            words: words.clone(),
            meeting_id: None,
            tasks: Vec::new(),
        })
    }

    pub fn dictations(&self, limit: i64) -> Result<Vec<Dictation>> {
        let c = self.0.lock().unwrap();
        let mut st = c.prepare(
            "SELECT d.id, d.text, d.duration_ms, d.created_at, d.audio_path, d.words, m.id
             FROM dictations d LEFT JOIN meetings m ON m.id = d.meeting_id
             ORDER BY d.id DESC LIMIT ?1",
        )?;
        let rows = st.query_map([limit], |r| {
            let audio: Option<String> = r.get(4)?;
            let words: Option<String> = r.get(5)?;
            Ok(Dictation {
                id: r.get(0)?,
                text: r.get(1)?,
                duration_ms: r.get(2)?,
                created_at: r.get(3)?,
                has_audio: audio.is_some_and(|p| Path::new(&p).exists()),
                words: words.and_then(|w| serde_json::from_str(&w).ok()).unwrap_or(serde_json::Value::Null),
                meeting_id: r.get(6)?,
                tasks: Vec::new(),
            })
        })?;
        let mut out: Vec<Dictation> = rows.collect::<Result<_, _>>()?;
        // Tasks from "Find tasks" on the recording, and from voice task recordings made during it.
        let mut st = c.prepare(
            "SELECT d.id, t.description, t.quote FROM tasks t
             JOIN meetings m ON m.id = t.meeting_id
             JOIN dictations d ON d.meeting_id = m.id OR m.dictation_id = d.id
             ORDER BY t.id",
        )?;
        let tasks = st.query_map([], |r| {
            Ok((r.get::<_, i64>(0)?, DictationTask { description: r.get(1)?, quote: r.get(2)? }))
        })?;
        let mut by_dictation: std::collections::HashMap<i64, Vec<DictationTask>> = Default::default();
        for t in tasks {
            let (d, t) = t?;
            by_dictation.entry(d).or_default().push(t);
        }
        for d in &mut out {
            d.tasks = by_dictation.remove(&d.id).unwrap_or_default();
        }
        Ok(out)
    }

    /// Voice task recordings made during a listening session belong to its recording.
    pub fn link_captures(&self, dictation_id: i64, capture_ids: &[i64]) -> Result<()> {
        let c = self.0.lock().unwrap();
        for id in capture_ids {
            c.execute("UPDATE meetings SET dictation_id = ?2 WHERE id = ?1", params![id, dictation_id])?;
        }
        Ok(())
    }

    /// Turn a Listen recording into a meeting (to be re-transcribed with speakers).
    /// Reuses its "Find tasks" holder so tasks aren't duplicated. Returns the
    /// meeting id and the recording's audio file, which the caller moves.
    pub fn dictation_into_meeting(&self, id: i64, title: &str) -> Result<(i64, Option<String>)> {
        let mut c = self.0.lock().unwrap();
        let tx = c.transaction()?;
        let (meeting_id, audio, created_at, duration_ms): (Option<i64>, Option<String>, String, i64) = tx.query_row(
            "SELECT meeting_id, audio_path, created_at, duration_ms FROM dictations WHERE id = ?1",
            [id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        )?;
        let meeting_id = match meeting_id {
            Some(m) => m,
            None => {
                tx.execute(
                    "INSERT INTO meetings (title, kind, started_at, status) VALUES (?1, 'meeting', ?2, 'transcribing')",
                    params![title, created_at],
                )?;
                tx.last_insert_rowid()
            }
        };
        tx.execute(
            "UPDATE meetings SET kind = 'meeting', title = ?2, status = 'transcribing', error = NULL,
                    ended_at = ?3, duration_s = ?4 WHERE id = ?1",
            params![meeting_id, title, now(), duration_ms as f64 / 1000.0],
        )?;
        // Voice task recordings made during it stay, but lose their recording.
        tx.execute("UPDATE meetings SET dictation_id = NULL WHERE dictation_id = ?1", [id])?;
        tx.execute("DELETE FROM dictations WHERE id = ?1", [id])?;
        tx.commit()?;
        Ok((meeting_id, audio))
    }

    /// Turn a meeting into a Listen recording. The meeting stays as the
    /// recording's hidden task holder, so its tasks and underlines are kept.
    pub fn meeting_into_dictation(
        &self,
        meeting_id: i64,
        text: &str,
        duration_ms: i64,
        audio_path: Option<&Path>,
        words: &serde_json::Value,
    ) -> Result<i64> {
        let mut c = self.0.lock().unwrap();
        let tx = c.transaction()?;
        let started_at: String = tx.query_row("SELECT started_at FROM meetings WHERE id = ?1", [meeting_id], |r| r.get(0))?;
        tx.execute(
            "INSERT INTO dictations (text, duration_ms, created_at, audio_path, words, meeting_id) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            params![
                text,
                duration_ms,
                started_at,
                audio_path.map(|p| p.to_string_lossy().to_string()),
                words.to_string(),
                meeting_id
            ],
        )?;
        let id = tx.last_insert_rowid();
        tx.execute("UPDATE meetings SET kind = 'dictation' WHERE id = ?1", [meeting_id])?;
        tx.commit()?;
        Ok(id)
    }

    pub fn set_dictation_meeting(&self, id: i64, meeting_id: i64) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("UPDATE dictations SET meeting_id = ?2 WHERE id = ?1", params![id, meeting_id])?;
        Ok(())
    }

    pub fn dictation_audio_path(&self, id: i64) -> Result<Option<String>> {
        let c = self.0.lock().unwrap();
        Ok(c
            .query_row("SELECT audio_path FROM dictations WHERE id = ?1", [id], |r| r.get(0))
            .optional()?
            .flatten())
    }

    /// Deletes the row; returns its audio file (if any) for the caller to remove.
    pub fn delete_dictation(&self, id: i64) -> Result<Option<String>> {
        let audio = self.dictation_audio_path(id)?;
        self.0.lock().unwrap().execute("DELETE FROM dictations WHERE id = ?1", [id])?;
        Ok(audio)
    }

    /// Detach recordings older than `days`; returns their files to delete. Text is kept.
    pub fn expire_dictation_audio(&self, days: u32) -> Result<Vec<String>> {
        let c = self.0.lock().unwrap();
        let cutoff = (chrono::Local::now() - chrono::Duration::days(days as i64)).to_rfc3339();
        let mut st = c.prepare("SELECT audio_path FROM dictations WHERE audio_path IS NOT NULL AND created_at < ?1")?;
        let paths = st.query_map([&cutoff], |r| r.get::<_, String>(0))?.collect::<Result<Vec<_>, _>>()?;
        c.execute("UPDATE dictations SET audio_path = NULL WHERE created_at < ?1", [&cutoff])?;
        Ok(paths)
    }

    // ---- meetings -------------------------------------------------------

    pub fn create_meeting(&self, title: &str, kind: &str) -> Result<i64> {
        let c = self.0.lock().unwrap();
        c.execute(
            "INSERT INTO meetings (title, kind, started_at, status) VALUES (?1, ?2, ?3, 'recording')",
            params![title, kind, now()],
        )?;
        Ok(c.last_insert_rowid())
    }

    pub fn set_meeting_status(&self, id: i64, status: &str, error: Option<&str>) -> Result<()> {
        let c = self.0.lock().unwrap();
        c.execute("UPDATE meetings SET status = ?2, error = ?3 WHERE id = ?1", params![id, status, error])?;
        if status == "transcribing" {
            c.execute("UPDATE meetings SET ended_at = COALESCE(ended_at, ?2) WHERE id = ?1", params![id, now()])?;
        }
        Ok(())
    }

    pub fn save_transcript(&self, id: i64, segments: &[Segment], duration_s: f64) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE meetings SET transcript = ?2, duration_s = ?3 WHERE id = ?1",
            params![id, serde_json::to_string(segments)?, duration_s],
        )?;
        Ok(())
    }

    pub fn save_summary(&self, id: i64, summary: &str) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("UPDATE meetings SET summary = ?2 WHERE id = ?1", params![id, summary])?;
        Ok(())
    }

    pub fn rename_meeting(&self, id: i64, title: &str) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("UPDATE meetings SET title = ?2 WHERE id = ?1", params![id, title])?;
        Ok(())
    }

    pub fn delete_meeting(&self, id: i64) -> Result<()> {
        self.0.lock().unwrap().execute("DELETE FROM meetings WHERE id = ?1", [id])?;
        Ok(())
    }

    pub fn meetings(&self) -> Result<Vec<Meeting>> {
        let c = self.0.lock().unwrap();
        let mut st = c.prepare(
            "SELECT m.id, m.title, m.kind, m.started_at, m.ended_at, m.status, m.error, m.duration_s, m.summary,
                    (SELECT COUNT(*) FROM tasks t WHERE t.meeting_id = m.id)
             FROM meetings m ORDER BY m.id DESC",
        )?;
        let rows = st.query_map([], |r| {
            Ok(Meeting {
                id: r.get(0)?,
                title: r.get(1)?,
                kind: r.get(2)?,
                started_at: r.get(3)?,
                ended_at: r.get(4)?,
                status: r.get(5)?,
                error: r.get(6)?,
                duration_s: r.get(7)?,
                summary: r.get(8)?,
                task_count: r.get(9)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    pub fn meeting(&self, id: i64) -> Result<Option<Meeting>> {
        Ok(self.meetings()?.into_iter().find(|m| m.id == id))
    }

    pub fn transcript(&self, id: i64) -> Result<Vec<Segment>> {
        let c = self.0.lock().unwrap();
        let raw: Option<String> = c
            .query_row("SELECT transcript FROM meetings WHERE id = ?1", [id], |r| r.get(0))
            .optional()?
            .flatten();
        Ok(raw.map(|s| serde_json::from_str(&s)).transpose()?.unwrap_or_default())
    }

    // ---- tasks ----------------------------------------------------------

    fn top_position(c: &Connection) -> rusqlite::Result<i64> {
        c.query_row("SELECT COALESCE(MIN(position), 0) FROM tasks", [], |r| r.get(0))
    }

    /// Replace a meeting's tasks; new tasks go to the top of the list, in order.
    pub fn replace_meeting_tasks(&self, meeting_id: i64, tasks: &[NewTask]) -> Result<()> {
        let mut c = self.0.lock().unwrap();
        let tx = c.transaction()?;
        tx.execute("DELETE FROM tasks WHERE meeting_id = ?1", [meeting_id])?;
        let top = Self::top_position(&tx)?;
        let created_at = now();
        for (i, t) in tasks.iter().enumerate() {
            tx.execute(
                "INSERT INTO tasks (meeting_id, description, assigned_by, due, quote, position, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                params![
                    meeting_id,
                    t.description,
                    t.assigned_by,
                    t.due,
                    t.quote,
                    top - (tasks.len() - i) as i64,
                    created_at
                ],
            )?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn add_task(&self, meeting_id: Option<i64>, t: &NewTask) -> Result<()> {
        let c = self.0.lock().unwrap();
        let top = Self::top_position(&c)?;
        c.execute(
            "INSERT INTO tasks (meeting_id, description, assigned_by, due, quote, position, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
            params![meeting_id, t.description, t.assigned_by, t.due, t.quote, top - 1, now()],
        )?;
        Ok(())
    }

    pub fn tasks(&self, meeting_id: Option<i64>) -> Result<Vec<Task>> {
        let c = self.0.lock().unwrap();
        let mut st = c.prepare(
            "SELECT t.id, t.meeting_id, m.title, t.description, t.assigned_by, t.due, t.quote, t.done, t.position, t.created_at, m.kind,
                    COALESCE(m.dictation_id, (SELECT d.id FROM dictations d WHERE d.meeting_id = m.id))
             FROM tasks t LEFT JOIN meetings m ON m.id = t.meeting_id
             WHERE (?1 IS NULL OR t.meeting_id = ?1)
             ORDER BY t.done ASC, t.position ASC, t.id DESC",
        )?;
        let rows = st.query_map([meeting_id], |r| {
            Ok(Task {
                id: r.get(0)?,
                meeting_id: r.get(1)?,
                meeting_title: r.get(2)?,
                description: r.get(3)?,
                assigned_by: r.get(4)?,
                due: r.get(5)?,
                quote: r.get(6)?,
                done: r.get::<_, i64>(7)? != 0,
                position: r.get(8)?,
                created_at: r.get(9)?,
                meeting_kind: r.get(10)?,
                dictation_id: r.get(11)?,
            })
        })?;
        Ok(rows.collect::<Result<_, _>>()?)
    }

    /// Put the given tasks in this order. Only their relative order changes, so
    /// reordering a filtered list (one meeting) keeps other tasks where they are.
    pub fn reorder_tasks(&self, ids: &[i64]) -> Result<()> {
        let mut c = self.0.lock().unwrap();
        let tx = c.transaction()?;
        let mut slots = Vec::with_capacity(ids.len());
        for id in ids {
            let pos: i64 = tx.query_row("SELECT position FROM tasks WHERE id = ?1", [id], |r| r.get(0))?;
            slots.push(pos);
        }
        slots.sort_unstable();
        // Duplicate positions (e.g. old data) would make the order ambiguous; spread them out.
        for i in 1..slots.len() {
            if slots[i] <= slots[i - 1] {
                slots[i] = slots[i - 1] + 1;
            }
        }
        for (id, pos) in ids.iter().zip(slots) {
            tx.execute("UPDATE tasks SET position = ?2 WHERE id = ?1", params![id, pos])?;
        }
        tx.commit()?;
        Ok(())
    }

    pub fn set_task_done(&self, id: i64, done: bool) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("UPDATE tasks SET done = ?2 WHERE id = ?1", params![id, done as i64])?;
        Ok(())
    }

    pub fn update_task(&self, id: i64, description: &str, due: Option<&str>) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE tasks SET description = ?2, due = ?3 WHERE id = ?1",
            params![id, description, due],
        )?;
        Ok(())
    }

    pub fn delete_task(&self, id: i64) -> Result<()> {
        self.0.lock().unwrap().execute("DELETE FROM tasks WHERE id = ?1", [id])?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn db() -> Db {
        let dir = std::env::temp_dir().join(format!("voicedesk-test-{}-{}", std::process::id(), rand_suffix()));
        std::fs::create_dir_all(&dir).unwrap();
        Db::open(&dir.join("t.db")).unwrap()
    }

    fn rand_suffix() -> u128 {
        std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
    }

    fn task(d: &str) -> NewTask {
        NewTask { description: d.into(), assigned_by: None, due: None, quote: None }
    }

    fn names(db: &Db, meeting: Option<i64>) -> Vec<String> {
        db.tasks(meeting).unwrap().into_iter().map(|t| t.description).collect()
    }

    #[test]
    fn converts_between_recording_and_meeting() {
        let db = db();
        let words = serde_json::json!([{ "w": "hello", "s": 0.0, "e": 0.5 }]);
        let d = db.add_dictation("hello", 1500, None, &words).unwrap();
        // A voice task recording made during it, and "Find tasks" on it.
        let cap = db.create_meeting("capture", "capture").unwrap();
        db.link_captures(d.id, &[cap]).unwrap();
        db.add_task(Some(cap), &task("from capture")).unwrap();
        let holder = db.create_meeting("holder", "dictation").unwrap();
        db.set_dictation_meeting(d.id, holder).unwrap();
        db.add_task(Some(holder), &task("found")).unwrap();
        let listed = db.dictations(10).unwrap();
        assert_eq!(listed[0].tasks.len(), 2, "both kinds of tasks underline the recording");
        let t = db.tasks(Some(cap)).unwrap();
        assert_eq!(t[0].dictation_id, Some(d.id));

        // Recording -> meeting: reuses the holder, recording is gone, capture unlinked.
        let (m, _) = db.dictation_into_meeting(d.id, "Meeting").unwrap();
        assert_eq!(m, holder);
        assert!(db.dictations(10).unwrap().is_empty());
        let meeting = db.meeting(m).unwrap().unwrap();
        assert_eq!((meeting.kind.as_str(), meeting.status.as_str()), ("meeting", "transcribing"));
        assert_eq!(db.tasks(Some(cap)).unwrap()[0].dictation_id, None);

        // Meeting -> recording: tasks kept and linked to the new recording.
        db.set_meeting_status(m, "done", None).unwrap();
        let back = db.meeting_into_dictation(m, "hello", 1500, None, &words).unwrap();
        assert_eq!(db.meeting(m).unwrap().unwrap().kind, "dictation");
        let listed = db.dictations(10).unwrap();
        assert_eq!((listed[0].id, listed[0].tasks.len()), (back, 1));
        assert_eq!(db.tasks(Some(m)).unwrap()[0].dictation_id, Some(back));
    }

    #[test]
    fn new_tasks_go_on_top_and_reorder_works() {
        let db = db();
        db.add_task(None, &task("a")).unwrap();
        db.add_task(None, &task("b")).unwrap();
        let m = db.create_meeting("m", "meeting").unwrap();
        db.replace_meeting_tasks(m, &[task("m1"), task("m2")]).unwrap();
        assert_eq!(names(&db, None), ["m1", "m2", "b", "a"]);

        let ids: Vec<i64> = db.tasks(None).unwrap().iter().map(|t| t.id).collect();
        // move "a" to the top
        db.reorder_tasks(&[ids[3], ids[0], ids[1], ids[2]]).unwrap();
        assert_eq!(names(&db, None), ["a", "m1", "m2", "b"]);

        // reordering within one meeting keeps other tasks in place
        let mids: Vec<i64> = db.tasks(Some(m)).unwrap().iter().map(|t| t.id).collect();
        db.reorder_tasks(&[mids[1], mids[0]]).unwrap();
        assert_eq!(names(&db, None), ["a", "m2", "m1", "b"]);
    }

    #[test]
    fn migrates_pre_migration_database() {
        let dir = std::env::temp_dir().join(format!("voicedesk-mig-{}", rand_suffix()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("old.db");
        {
            let c = Connection::open(&path).unwrap();
            c.execute_batch(MIGRATIONS[0]).unwrap();
            c.execute("INSERT INTO tasks (description, created_at) VALUES ('old1', 'x')", []).unwrap();
            c.execute("INSERT INTO tasks (description, created_at) VALUES ('old2', 'x')", []).unwrap();
        }
        let db = Db::open(&path).unwrap();
        assert_eq!(names(&db, None), ["old2", "old1"]);
        db.create_meeting("t", "capture").unwrap();
        assert_eq!(db.meetings().unwrap()[0].kind, "capture");
    }
}
