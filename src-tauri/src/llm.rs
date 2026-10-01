//! Task extraction with a local LLM (Qwen3 4B) served by Ollama.
//! Ollama is started automatically if it's installed but not running.

use std::path::PathBuf;
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::db::{NewTask, Segment, Settings};

/// ~3k tokens per chunk keeps prompt + reply inside an 8k context, which fits a 4 GB GPU.
const CHUNK_CHARS: usize = 12_000;
const OVERLAP_CHARS: usize = 1_500;
/// Most context the task AI gets (tokens). Each request asks only for what its
/// text needs: on a 4 GB GPU a full 8K context alone takes ~0.6 GB.
const MAX_CTX: u32 = 8192;
const MIN_CTX: u32 = 2048;
/// Room for the answer (summary + tasks as JSON).
const ANSWER_TOKENS: u32 = 1536;

/// Context size for a prompt: roughly 3.5 English characters per token, and
/// about one token per character of Hindi/Gujarati script. Rounded up to 1K.
pub fn context_for(prompt: &str) -> u32 {
    let (ascii, other) = prompt.chars().fold((0u32, 0u32), |(a, o), c| if c.is_ascii() { (a + 1, o) } else { (a, o + 1) });
    let need = ascii * 2 / 7 + other + ANSWER_TOKENS;
    need.div_ceil(1024).saturating_mul(1024).clamp(MIN_CTX, MAX_CTX)
}

/// Ollama options that follow the Processor setting: CPU keeps every layer
/// off the GPU; a chosen GPU is used first. CPU work uses half the cores.
pub fn device_options(device: &str, prompt: &str) -> Value {
    let mut o = json!({
        "temperature": 0.1,
        "num_ctx": context_for(prompt),
        // A confused model on a slow laptop could otherwise write until the context is full.
        "num_predict": ANSWER_TOKENS,
        "num_thread": crate::hardware::worker_threads(),
    });
    if device == "cpu" {
        o["num_gpu"] = json!(0);
    } else if let Some(i) = device.strip_prefix("cuda:").and_then(|i| i.parse::<u32>().ok()) {
        o["main_gpu"] = json!(i);
    }
    o
}

#[derive(Debug, Deserialize)]
pub struct Extraction {
    pub summary: String,
    pub tasks: Vec<NewTask>,
}

fn schema() -> Value {
    let nullable = json!({ "type": ["string", "null"] });
    json!({
        "type": "object",
        "properties": {
            "summary": { "type": "string" },
            "tasks": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "description": { "type": "string" },
                        "assigned_by": nullable,
                        "due": nullable,
                        "quote": nullable
                    },
                    "required": ["description", "assigned_by", "due", "quote"]
                }
            }
        },
        "required": ["summary", "tasks"]
    })
}

fn fmt_time(s: f64) -> String {
    let s = s as u64;
    format!("{:02}:{:02}", s / 60, s % 60)
}

pub fn format_transcript(segments: &[Segment]) -> String {
    let mut out = String::new();
    let mut last_speaker = "";
    for s in segments {
        if s.speaker != last_speaker {
            out.push_str(&format!("\n[{}] {}: ", fmt_time(s.start), s.speaker));
            last_speaker = &s.speaker;
        } else {
            out.push(' ');
        }
        out.push_str(&s.text);
    }
    out.trim().to_string()
}

/// Split on line boundaries, carrying a little context from the previous chunk.
fn chunk(text: &str) -> Vec<String> {
    if text.len() <= CHUNK_CHARS {
        return vec![text.to_string()];
    }
    let mut chunks = Vec::new();
    let mut current = String::new();
    for line in text.lines() {
        if current.len() + line.len() > CHUNK_CHARS && !current.is_empty() {
            let mut cut = current.len().saturating_sub(OVERLAP_CHARS);
            while !current.is_char_boundary(cut) {
                cut += 1;
            }
            let tail = current[cut..].to_string();
            chunks.push(std::mem::take(&mut current));
            current = format!("(…continued) {tail}\n");
        }
        current.push_str(line);
        current.push('\n');
    }
    if !current.trim().is_empty() {
        chunks.push(current);
    }
    chunks
}

fn who_am_i(settings: &Settings) -> String {
    let name = if settings.user_name.trim().is_empty() { "the user" } else { settings.user_name.trim() };
    let mut s = format!("The user's name is \"{name}\".");
    if !settings.aliases.trim().is_empty() {
        s += &format!(" People may also call them: {}.", settings.aliases.trim());
    }
    s += " Lines labelled \"Me\" were spoken by the user.";
    s
}

const SYSTEM: &str = "You are an assistant that reads meeting transcripts and extracts the action items \
that belong to ONE specific person (the user). Transcripts come from speech recognition and may contain \
errors; speaker labels like \"Speaker 1\" are other participants. The conversation may mix English, Hindi \
and Gujarati; understand all of them, but always write the summary and tasks in English.\n\
Include a task when:\n\
- someone asks, tells, or assigns the user to do something (by name, or by talking to them directly), or\n\
- the user commits to doing something (e.g. \"I'll send the deck\", \"let me look into it\").\n\
Do NOT include tasks that belong to other people, general discussion, or things already completed.\n\
For each task:\n\
- description: a short imperative phrase starting with a verb (\"Send the Q3 deck to Priya\").\n\
- assigned_by: the speaker who asked, \"Self\" if the user volunteered, or null if unclear.\n\
- due: the deadline exactly as stated (\"by Friday\", \"end of day\"), or null.\n\
- quote: the shortest verbatim transcript excerpt that shows the assignment.\n\
summary: 2-4 sentences on what the meeting covered and decided.\n\
If there are no tasks for the user, return an empty tasks array. Never invent tasks.";

const SYSTEM_SELF: &str = "You are an assistant that turns what a person dictated to themselves into a to-do list. \
The text comes from speech recognition and may contain errors, and may mix English, Hindi and Gujarati; \
always write the summary and tasks in English. Lines labelled \"Me\" are the user.\n\
Extract every task, to-do, or reminder the user mentions for themselves (\"I need to call the bank\", \
\"remind me to book tickets\", \"buy milk\").\n\
For each task:\n\
- description: a short imperative phrase starting with a verb (\"Call the bank\").\n\
- assigned_by: \"Self\".\n\
- due: when it should happen exactly as stated (\"tomorrow morning\", \"next week\"), or null.\n\
- quote: the shortest verbatim excerpt the task comes from.\n\
summary: one sentence describing what the user noted.\n\
If nothing is a task, return an empty tasks array. Never invent tasks.";

/// Meeting: tasks others give the user (plus the user's own commitments).
/// SelfNotes: the user was alone, dictating their own to-dos.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Mode {
    Meeting,
    SelfNotes,
}

pub struct Llm {
    http: reqwest::Client,
    /// The `ollama serve` we started, so it can be stopped when Voice Desk exits.
    spawned: std::sync::Mutex<Option<std::process::Child>>,
}

#[derive(serde::Serialize)]
pub struct LlmStatus {
    pub installed: bool,
    pub running: bool,
    pub model_ready: bool,
    pub message: String,
}

/// Where Ollama usually lives, plus whatever is on PATH.
fn find_ollama() -> Option<PathBuf> {
    let exe = if cfg!(windows) { "ollama.exe" } else { "ollama" };
    let mut candidates: Vec<PathBuf> = std::env::var_os("PATH")
        .map(|p| std::env::split_paths(&p).map(|d| d.join(exe)).collect())
        .unwrap_or_default();
    if cfg!(windows) {
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            candidates.push(PathBuf::from(local).join("Programs").join("Ollama").join(exe));
        }
    } else if cfg!(target_os = "macos") {
        candidates.push("/Applications/Ollama.app/Contents/Resources/ollama".into());
        candidates.push("/opt/homebrew/bin/ollama".into());
        candidates.push("/usr/local/bin/ollama".into());
    } else {
        candidates.push("/usr/local/bin/ollama".into());
        candidates.push("/usr/bin/ollama".into());
    }
    candidates.into_iter().find(|p| p.is_file())
}

fn is_local(url: &str) -> bool {
    url.contains("127.0.0.1") || url.contains("localhost")
}

impl Llm {
    pub fn new() -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(Duration::from_secs(900))
                .build()
                .expect("http client"),
            spawned: std::sync::Mutex::new(None),
        }
    }

    /// Stop the Ollama server Voice Desk started (an Ollama that was already
    /// running before Voice Desk opened is left alone).
    pub fn shutdown(&self) {
        let Some(mut child) = self.spawned.lock().unwrap().take() else { return };
        #[cfg(windows)]
        {
            // Also ends the model runner processes Ollama started.
            use std::os::windows::process::CommandExt;
            let _ = std::process::Command::new("taskkill")
                .args(["/PID", &child.id().to_string(), "/T", "/F"])
                .creation_flags(0x0800_0000)
                .status();
        }
        let _ = child.kill();
        let _ = child.wait();
    }

    fn url(settings: &Settings, path: &str) -> String {
        format!("{}{path}", settings.ollama_url.trim_end_matches('/'))
    }

    async fn tags(&self, settings: &Settings) -> Option<Value> {
        let resp = self
            .http
            .get(Self::url(settings, "/api/tags"))
            .timeout(Duration::from_secs(3))
            .send()
            .await
            .ok()?;
        resp.json().await.ok()
    }

    fn has_model(tags: &Value, model: &str) -> bool {
        let want = if model.contains(':') { model.to_string() } else { format!("{model}:latest") };
        tags["models"]
            .as_array()
            .map(|a| a.iter().any(|m| m["name"].as_str() == Some(want.as_str())))
            .unwrap_or(false)
    }

    /// Start `ollama serve` in the background if it's installed but not running.
    pub async fn ensure_running(&self, settings: &Settings) -> Result<()> {
        if self.tags(settings).await.is_some() {
            return Ok(());
        }
        if !is_local(&settings.ollama_url) {
            return Err(anyhow!("Could not reach Ollama at {}", settings.ollama_url));
        }
        let bin = find_ollama()
            .ok_or_else(|| anyhow!("Ollama is not installed. Download it from https://ollama.com/download"))?;
        let mut cmd = std::process::Command::new(bin);
        cmd.arg("serve")
            // Half-size working memory (KV cache) with no loss worth noticing in task extraction.
            .env("OLLAMA_FLASH_ATTENTION", "1")
            .env("OLLAMA_KV_CACHE_TYPE", "q8_0")
            .stdin(std::process::Stdio::null())
            .stdout(std::process::Stdio::null())
            .stderr(std::process::Stdio::null());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
        }
        let child = cmd.spawn().context("could not start Ollama")?;
        *self.spawned.lock().unwrap() = Some(child);
        for _ in 0..40 {
            tokio::time::sleep(Duration::from_millis(500)).await;
            if self.tags(settings).await.is_some() {
                return Ok(());
            }
        }
        Err(anyhow!("Ollama was started but isn't responding"))
    }

    pub async fn status(&self, settings: &Settings) -> LlmStatus {
        let installed = find_ollama().is_some() || !is_local(&settings.ollama_url);
        let running = installed && self.ensure_running(settings).await.is_ok();
        let tags = if running { self.tags(settings).await } else { None };
        let model_ready = tags.as_ref().is_some_and(|t| Self::has_model(t, &settings.llm_model));
        let message = if !installed {
            "Ollama is not installed. Download it from https://ollama.com/download".into()
        } else if !running {
            "Ollama is installed but could not be started.".into()
        } else if !model_ready {
            format!("The '{}' model needs to be downloaded (about 2.5 GB).", settings.llm_model)
        } else {
            format!("Ready: '{}'", settings.llm_model)
        };
        LlmStatus { installed, running, model_ready, message }
    }

    /// Download the model, reporting (status, percent or -1).
    pub async fn pull(&self, settings: &Settings, mut on_progress: impl FnMut(&str, f64)) -> Result<()> {
        self.ensure_running(settings).await?;
        let mut resp = self
            .http
            .post(Self::url(settings, "/api/pull"))
            .timeout(Duration::from_secs(6 * 3600))
            .json(&json!({ "model": settings.llm_model, "stream": true }))
            .send()
            .await?;
        let mut buf = Vec::new();
        while let Some(chunk) = resp.chunk().await? {
            buf.extend_from_slice(&chunk);
            while let Some(nl) = buf.iter().position(|&b| b == b'\n') {
                let line: Vec<u8> = buf.drain(..=nl).collect();
                let Ok(v) = serde_json::from_slice::<Value>(&line) else { continue };
                if let Some(e) = v["error"].as_str() {
                    return Err(anyhow!("download failed: {e}"));
                }
                let pct = match (v["completed"].as_f64(), v["total"].as_f64()) {
                    (Some(c), Some(t)) if t > 0.0 => c / t * 100.0,
                    _ => -1.0,
                };
                on_progress(v["status"].as_str().unwrap_or(""), pct);
            }
        }
        Ok(())
    }

    async fn chat(&self, settings: &Settings, system: &str, user: &str) -> Result<Value> {
        let body = json!({
            "model": settings.llm_model,
            "stream": false,
            "think": false,
            "format": schema(),
            // Free GPU/RAM soon after extraction instead of Ollama's default 5 minutes.
            "keep_alive": "1m",
            "options": device_options(&settings.whisper_device, &format!("{system}{user}")),
            "messages": [
                { "role": "system", "content": system },
                { "role": "user", "content": user }
            ]
        });
        let resp = self.http.post(Self::url(settings, "/api/chat")).json(&body).send().await?;
        let status = resp.status();
        let v: Value = resp.json().await?;
        if !status.is_success() {
            let msg = v["error"].as_str().unwrap_or("unknown");
            if msg.contains("not found") {
                return Err(anyhow!(
                    "The '{}' model isn't downloaded yet. Open Settings → Setup to download it.",
                    settings.llm_model
                ));
            }
            return Err(anyhow!("Ollama error {status}: {msg}"));
        }
        let content = v["message"]["content"].as_str().context("empty LLM response")?;
        serde_json::from_str(content).with_context(|| format!("LLM returned invalid JSON: {content}"))
    }

    pub async fn extract(
        &self,
        settings: &Settings,
        title: &str,
        segments: &[Segment],
        mode: Mode,
        on_progress: impl FnMut(usize, usize),
    ) -> Result<Extraction> {
        let mut e = self.extract_raw(settings, title, segments, mode, on_progress).await?;
        // Small models sometimes garble labels ("Speaker :1"); snap them back to real speakers.
        let key = |s: &str| s.chars().filter(|c| c.is_alphanumeric()).collect::<String>().to_lowercase();
        for t in &mut e.tasks {
            if let Some(by) = t.assigned_by.as_mut() {
                if key(by) == "me" || key(by) == "self" {
                    *by = "Self".into();
                } else if let Some(s) = segments.iter().find(|s| key(&s.speaker) == key(by)) {
                    *by = s.speaker.clone();
                }
            }
        }
        e.tasks.retain(|t| !t.description.trim().is_empty());
        Ok(e)
    }

    async fn extract_raw(
        &self,
        settings: &Settings,
        title: &str,
        segments: &[Segment],
        mode: Mode,
        mut on_progress: impl FnMut(usize, usize),
    ) -> Result<Extraction> {
        let transcript = format_transcript(segments);
        if transcript.trim().is_empty() {
            return Ok(Extraction { summary: "No speech was detected.".into(), tasks: vec![] });
        }
        self.ensure_running(settings).await?;
        let chunks = chunk(&transcript);
        let me = who_am_i(settings);
        let (system, ask) = match mode {
            Mode::Meeting => (SYSTEM, "Extract the user's action items and summarize."),
            Mode::SelfNotes => (SYSTEM_SELF, "Extract the user's to-dos and summarize."),
        };
        let mut summaries = Vec::new();
        let mut tasks = Vec::new();

        for (i, c) in chunks.iter().enumerate() {
            on_progress(i, chunks.len());
            let part = if chunks.len() > 1 {
                format!(" (part {} of {})", i + 1, chunks.len())
            } else {
                String::new()
            };
            let prompt = format!("{me}\nTitle: \"{title}\"{part}\n\nTranscript:\n\"\"\"\n{c}\n\"\"\"\n\n{ask}");
            let v = self.chat(settings, system, &prompt).await?;
            let e: Extraction = serde_json::from_value(v)?;
            summaries.push(e.summary);
            tasks.extend(e.tasks);
        }

        if chunks.len() == 1 {
            return Ok(Extraction { summary: summaries.remove(0), tasks });
        }

        // Several chunks: merge partial summaries and drop duplicate tasks from overlaps.
        on_progress(chunks.len(), chunks.len());
        let prompt = format!(
            "{me}\nThese are partial results from consecutive parts of one recording (\"{title}\").\n\
             Partial summaries:\n{}\n\nCandidate tasks (JSON):\n{}\n\n\
             Write one combined summary and return the task list with duplicates merged. \
             Keep every distinct task; do not add new ones.",
            summaries.iter().map(|s| format!("- {s}")).collect::<Vec<_>>().join("\n"),
            serde_json::to_string_pretty(
                &tasks
                    .iter()
                    .map(|t| json!({"description": t.description, "assigned_by": t.assigned_by, "due": t.due, "quote": t.quote}))
                    .collect::<Vec<_>>()
            )?
        );
        let v = self
            .chat(settings, "You merge meeting notes. Output only the requested JSON.", &prompt)
            .await?;
        Ok(serde_json::from_value(v)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn context_fits_the_prompt() {
        assert_eq!(context_for("short"), MIN_CTX);
        assert_eq!(context_for(&"word ".repeat(2000)), 5120); // 10K chars ≈ 2.9K tokens + answer
        assert_eq!(context_for(&"ક".repeat(4000)), 6144); // Gujarati: ~1 token per character
        assert_eq!(context_for(&"x".repeat(100_000)), MAX_CTX);
        assert_eq!(device_options("cpu", "")["num_gpu"], 0);
        assert_eq!(device_options("cuda:1", "")["main_gpu"], 1);
        assert!(device_options("auto", "").get("num_gpu").is_none());
    }

    fn seg(start: f64, speaker: &str, text: &str) -> Segment {
        Segment { start, end: start + 4.0, speaker: speaker.into(), text: text.into(), words: None }
    }

    /// Needs a running Ollama with qwen3:4b. Run: cargo test -- --ignored --nocapture
    #[tokio::test(flavor = "current_thread")]
    #[ignore]
    async fn extracts_only_my_tasks() {
        let settings = Settings { user_name: "Rajvee".into(), ..Settings::default() };
        let segments = vec![
            seg(0.0, "Speaker 1", "Okay let's get started. Quick updates on the launch."),
            seg(6.0, "Me", "The login page is done, I'm waiting on design review."),
            seg(12.0, "Speaker 1", "Great. Rajvee, can you send the quarterly report to Priya by Friday?"),
            seg(18.0, "Me", "Sure, I'll do that. I'll also fix the signup bug before tomorrow's standup."),
            seg(25.0, "Speaker 2", "I'll take care of the marketing email this week."),
            seg(31.0, "Speaker 1", "Thanks. Priya, please update the roadmap slide."),
        ];
        let e = Llm::new().extract(&settings, "Launch sync", &segments, Mode::Meeting, |_, _| {}).await.unwrap();
        println!("summary: {}", e.summary);
        for t in &e.tasks {
            println!("- {} | by {:?} | due {:?} | {:?}", t.description, t.assigned_by, t.due, t.quote);
        }
        let all = e.tasks.iter().map(|t| t.description.to_lowercase()).collect::<Vec<_>>().join(" | ");
        assert!(all.contains("report"), "missing report task: {all}");
        assert!(all.contains("signup") || all.contains("sign-up") || all.contains("bug"), "missing bug task: {all}");
        assert!(!all.contains("marketing") && !all.contains("roadmap"), "included others' tasks: {all}");
    }

    /// The user's own test meeting: someone assigns two tasks to "Nishchay".
    #[tokio::test(flavor = "current_thread")]
    #[ignore]
    async fn tasks_assigned_by_name() {
        let settings = Settings { user_name: "Nishchay".into(), ..Settings::default() };
        let segments = vec![
            seg(0.0, "Speaker 1", "Hello, hello, good morning to everyone. Nishchay, you need to complete doing this task, which is eating an apple."),
            seg(9.5, "Speaker 1", "And Nishchay, I am giving you another task of playing games."),
        ];
        let e = Llm::new().extract(&settings, "Test", &segments, Mode::Meeting, |_, _| {}).await.unwrap();
        for t in &e.tasks {
            println!("- {} | by {:?} | due {:?}", t.description, t.assigned_by, t.due);
        }
        let all = e.tasks.iter().map(|t| t.description.to_lowercase()).collect::<Vec<_>>().join(" | ");
        assert!(all.contains("apple") && all.contains("game"), "{all}");
    }

    /// "Jarvis, record tasks" while alone: the user's own to-dos.
    #[tokio::test(flavor = "current_thread")]
    #[ignore]
    async fn self_notes() {
        let settings = Settings { user_name: "Nishchay".into(), ..Settings::default() };
        let segments = vec![seg(
            0.0,
            "Me",
            "I need to call the bank tomorrow morning and renew my passport next week. Also buy milk.",
        )];
        let e = Llm::new().extract(&settings, "Notes", &segments, Mode::SelfNotes, |_, _| {}).await.unwrap();
        for t in &e.tasks {
            println!("- {} | by {:?} | due {:?}", t.description, t.assigned_by, t.due);
        }
        assert_eq!(e.tasks.len(), 3, "{:?}", e.tasks.iter().map(|t| &t.description).collect::<Vec<_>>());
    }
}
