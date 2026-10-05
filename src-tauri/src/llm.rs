//! Task extraction with a local LLM (Qwen3) run by llama.cpp's `llama-server`.
//!
//! Voice Desk downloads the server (~20-35 MB) and the model itself, starts the
//! server only while finding tasks, and stops it a minute later to free the
//! memory. Replaces Ollama, which was a separate 2.8 GB install.

use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use serde::Deserialize;
use serde_json::{json, Value};

use crate::db::{NewTask, Segment, Settings};

/// ~3k tokens per chunk keeps prompt + reply inside an 8k context, which fits a 4 GB GPU.
const CHUNK_CHARS: usize = 12_000;
const OVERLAP_CHARS: usize = 1_500;
/// Most context the task AI gets (tokens). Each job asks only for what its
/// text needs: on a 4 GB GPU a full 8K context alone takes ~0.6 GB.
const MAX_CTX: u32 = 8192;
const MIN_CTX: u32 = 2048;
/// Room for the answer (summary + tasks as JSON); also the most it may write.
const ANSWER_TOKENS: u32 = 1536;
/// The server is stopped this long after the last request, freeing its memory.
const IDLE_STOP: Duration = Duration::from_secs(60);

/// llama.cpp build to download (pinned: the same server everywhere).
const LLAMA_BUILD: &str = "b11320";

/// Context size for a prompt: roughly 3.5 English characters per token, and
/// about one token per character of Hindi/Gujarati script. Rounded up to 1K.
pub fn context_for(prompt: &str) -> u32 {
    let (ascii, other) = prompt.chars().fold((0u32, 0u32), |(a, o), c| if c.is_ascii() { (a + 1, o) } else { (a, o + 1) });
    let need = ascii * 2 / 7 + other + ANSWER_TOKENS;
    need.div_ceil(1024).saturating_mul(1024).clamp(MIN_CTX, MAX_CTX)
}

/// The task models Voice Desk offers (Settings -> Task AI).
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum TaskModel {
    /// Qwen3 1.7B: 1.1 GB. Lighter but less accurate: in the task tests it
    /// copied an example from its instructions and invented due dates (1 of 3 failed).
    Small,
    /// Qwen3 4B: 2.5 GB, finds tasks more reliably.
    Large,
}

impl TaskModel {
    /// "auto": the 4B (passes all task tests; ~3 GB of RAM while running),
    /// unless the computer has under 6 GB of RAM. "qwen3-1.7b" / "qwen3-4b" choose.
    pub fn from_setting(value: &str, ram_gb: f64) -> Self {
        match value {
            "qwen3-1.7b" => Self::Small,
            "qwen3-4b" => Self::Large,
            _ if ram_gb >= 6.0 => Self::Large,
            _ => Self::Small,
        }
    }
    pub fn file(self) -> &'static str {
        match self {
            Self::Small => "Qwen3-1.7B-Q4_K_M.gguf",
            Self::Large => "Qwen3-4B-Q4_K_M.gguf",
        }
    }
    /// Pinned to a commit: the same file everywhere, matching its SHA-256 in downloads.rs.
    pub fn url(self) -> String {
        let (repo, commit) = match self {
            Self::Small => ("unsloth/Qwen3-1.7B-GGUF", "d7f544eead698dbd1f15126ef60b45a1e1933222"),
            Self::Large => ("unsloth/Qwen3-4B-GGUF", "22c9fc8a8c7700b76a1789366280a6a5a1ad1120"),
        };
        format!("https://huggingface.co/{repo}/resolve/{commit}/{}", self.file())
    }
    /// Download size, for the free-space check.
    fn size_gb(self) -> f64 {
        match self {
            Self::Small => 1.1,
            Self::Large => 2.5,
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::Small => "Qwen3 1.7B (1.1 GB)",
            Self::Large => "Qwen3 4B (2.5 GB)",
        }
    }
}

fn ram_gb() -> f64 {
    let mut sys = sysinfo::System::new();
    sys.refresh_memory();
    sys.total_memory() as f64 / 1e9
}

/// The model the current settings use.
pub fn task_model(settings: &Settings) -> TaskModel {
    TaskModel::from_setting(&settings.llm_model, ram_gb())
}

/// Vulkan runs on NVIDIA, AMD and Intel GPUs without CUDA libraries; it needs
/// the GPU driver's Vulkan loader. Without one, the CPU build.
fn has_vulkan() -> bool {
    if cfg!(windows) {
        std::env::var_os("SystemRoot").is_some_and(|r| PathBuf::from(r).join("System32").join("vulkan-1.dll").exists())
    } else if cfg!(target_os = "linux") {
        ["/usr/lib/x86_64-linux-gnu/libvulkan.so.1", "/usr/lib/libvulkan.so.1", "/usr/lib64/libvulkan.so.1"]
            .iter()
            .any(|p| std::path::Path::new(p).exists())
    } else {
        false // macOS builds use Metal
    }
}

/// (download name, folder name) of the llama.cpp build for this computer.
fn server_build() -> (String, String) {
    let flavour = match (std::env::consts::OS, std::env::consts::ARCH) {
        ("windows", _) if has_vulkan() => "win-vulkan-x64.zip",
        ("windows", _) => "win-cpu-x64.zip",
        ("macos", "aarch64") => "macos-arm64.tar.gz",
        ("macos", _) => "macos-x64.tar.gz",
        ("linux", "aarch64") => "ubuntu-arm64.tar.gz",
        _ if has_vulkan() => "ubuntu-vulkan-x64.tar.gz",
        _ => "ubuntu-x64.tar.gz",
    };
    let file = format!("llama-{LLAMA_BUILD}-bin-{flavour}");
    let folder = file.trim_end_matches(".zip").trim_end_matches(".tar.gz").to_string();
    (file, folder)
}

fn server_dir() -> PathBuf {
    crate::system::voicedesk_models_dir().parent().map(|p| p.join("llama")).unwrap_or_default().join(server_build().1)
}

fn server_exe() -> PathBuf {
    server_dir().join(if cfg!(windows) { "llama-server.exe" } else { "llama-server" })
}

fn model_path(m: TaskModel) -> PathBuf {
    crate::system::voicedesk_models_dir().join(m.file())
}

/// llama.cpp's Windows builds need the Visual C++ runtime, which a fresh Windows
/// doesn't have and the zip doesn't include (without it llama-server won't
/// start). Voice Desk ships these (Microsoft allows app-local copies, see build.rs).
const VC_RUNTIME: [&str; 3] = ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"];

/// Put any missing Visual C++ runtime DLL beside llama-server (also fixes
/// installs unpacked before Voice Desk shipped them).
fn add_vc_runtime(redist: Option<&Path>, dir: &Path) {
    let Some(redist) = redist.filter(|_| cfg!(windows)) else { return };
    for dll in VC_RUNTIME {
        let to = dir.join(dll);
        if !to.exists() {
            if let Err(e) = std::fs::copy(redist.join(dll), &to) {
                eprintln!("[llm] couldn't add {dll}: {e}");
            }
        }
    }
}

/// Arguments for `llama-server`. CPU only keeps every layer off the GPU; heavy
/// work uses half the CPU cores, for reading the prompt (`-tb`) as well as
/// writing; idle threads sleep instead of spinning (`--poll 0`), and two HTTP
/// threads are plenty for one request at a time. The working memory (KV cache)
/// is 8-bit.
pub fn server_args(model: &std::path::Path, port: u16, ctx: u32, device: &str, threads: usize) -> Vec<String> {
    let mut a: Vec<String> = vec![
        "-m".into(),
        model.to_string_lossy().into(),
        "--host".into(),
        "127.0.0.1".into(),
        "--port".into(),
        port.to_string(),
        "-c".into(),
        ctx.to_string(),
        "-np".into(),
        "1".into(),
        "-t".into(),
        threads.to_string(),
        "-tb".into(),
        threads.to_string(),
        "--poll".into(),
        "0".into(),
        "--threads-http".into(),
        "2".into(),
        "--jinja".into(), // Qwen3's chat template (lets thinking be turned off)
        "--no-webui".into(),
        "-fa".into(),
        "on".into(),
        "--cache-type-k".into(),
        "q8_0".into(),
        "--cache-type-v".into(),
        "q8_0".into(),
        "-ngl".into(),
        if device == "cpu" { "0" } else { "99" }.into(),
    ];
    if device == "cpu" {
        // Without this the Vulkan build still opens the GPU (~0.1 GB) with no layers on it.
        a.extend(["--device".into(), "none".into()]);
    }
    a
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

struct Server {
    child: std::process::Child,
    port: u16,
    ctx: u32,
    model: TaskModel,
    device: String,
}

pub struct Llm {
    http: reqwest::Client,
    server: Arc<Mutex<Option<Server>>>,
    /// Bumped when a request starts and when it ends; an idle timer only stops
    /// a server nothing has used since the timer was set.
    used: Arc<AtomicU64>,
    /// Requests being answered: the idle timer never stops the server under one.
    in_flight: Arc<AtomicUsize>,
    /// One job at a time (the server has one slot).
    busy: tokio::sync::Mutex<()>,
    /// The Visual C++ runtime DLLs shipped with Voice Desk (Windows).
    redist: Option<PathBuf>,
}

/// A request to the server; when it ends (however it ends), the idle timer starts.
struct InFlight<'a>(&'a Llm);

impl<'a> InFlight<'a> {
    fn new(llm: &'a Llm) -> Self {
        llm.in_flight.fetch_add(1, Ordering::SeqCst);
        llm.used.fetch_add(1, Ordering::SeqCst);
        Self(llm)
    }
}

impl Drop for InFlight<'_> {
    fn drop(&mut self) {
        self.0.in_flight.fetch_sub(1, Ordering::SeqCst);
        self.0.stop_when_idle();
    }
}

/// Nothing is being answered, and no request started or ended since `used` was `n`.
fn unused_since(in_flight: &AtomicUsize, used: &AtomicU64, n: u64) -> bool {
    in_flight.load(Ordering::SeqCst) == 0 && used.load(Ordering::SeqCst) == n
}

#[derive(serde::Serialize)]
pub struct LlmStatus {
    /// The server program is downloaded.
    pub installed: bool,
    pub running: bool,
    /// The model the settings use is downloaded.
    pub model_ready: bool,
    /// "Qwen3 4B (2.5 GB)"
    pub model: String,
    pub message: String,
}

/// Windows: put a helper process in a job that Windows ends together with
/// Voice Desk (even if Voice Desk crashes), so it never lingers holding GBs of RAM.
#[cfg(windows)]
fn end_with_voice_desk(child: &std::process::Child) {
    use std::os::windows::io::AsRawHandle;
    use std::sync::OnceLock;
    use windows::Win32::Foundation::HANDLE;
    use windows::Win32::System::JobObjects::{
        AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation, SetInformationJobObject,
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
    };
    static JOB: OnceLock<usize> = OnceLock::new();
    let job = *JOB.get_or_init(|| unsafe {
        let Ok(job) = CreateJobObjectW(None, None) else { return 0 };
        let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let _ = SetInformationJobObject(
            job,
            JobObjectExtendedLimitInformation,
            &info as *const _ as *const std::ffi::c_void,
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        );
        job.0 as usize // kept open for Voice Desk's lifetime
    });
    if job != 0 {
        unsafe {
            let _ = AssignProcessToJobObject(HANDLE(job as *mut _), HANDLE(child.as_raw_handle()));
        }
    }
}

#[cfg(not(windows))]
fn end_with_voice_desk(_child: &std::process::Child) {}

fn free_port() -> Result<u16> {
    Ok(std::net::TcpListener::bind("127.0.0.1:0")?.local_addr()?.port())
}

fn stop(server: &mut Option<Server>) {
    if let Some(mut s) = server.take() {
        let _ = s.child.kill();
        let _ = s.child.wait();
    }
}

impl Drop for Llm {
    fn drop(&mut self) {
        self.shutdown();
    }
}

impl Llm {
    /// `redist`: the folder with the Visual C++ runtime DLLs (Windows; see `VC_RUNTIME`).
    pub fn new(redist: Option<PathBuf>) -> Self {
        Self {
            http: reqwest::Client::builder().timeout(Duration::from_secs(900)).build().expect("http client"),
            server: Arc::new(Mutex::new(None)),
            used: Arc::new(AtomicU64::new(0)),
            in_flight: Arc::new(AtomicUsize::new(0)),
            busy: tokio::sync::Mutex::new(()),
            redist,
        }
    }

    /// Stop the task AI (Voice Desk is closing).
    pub fn shutdown(&self) {
        stop(&mut self.server.lock().unwrap());
    }

    /// The server's process id while it runs (for its memory use).
    pub fn pid(&self) -> Option<u32> {
        self.server.lock().unwrap().as_ref().map(|s| s.child.id())
    }

    pub fn status(&self, settings: &Settings) -> LlmStatus {
        let model = task_model(settings);
        let installed = server_exe().exists();
        let model_ready = model_path(model).exists();
        let running = self.server.lock().unwrap().is_some();
        let message = if !installed || !model_ready {
            format!("Download the task AI to find tasks ({} plus a ~30 MB runner).", model.label())
        } else {
            format!("Ready: {}", model.label())
        };
        LlmStatus { installed, running, model_ready, model: model.label().into(), message }
    }

    /// Download the server and the model the settings use; `on_progress(status, percent)`.
    pub async fn pull(&self, settings: &Settings, mut on_progress: impl FnMut(&str, f64)) -> Result<()> {
        let model = task_model(settings);
        let need = [(!server_exe().exists(), 0.1), (!model_path(model).exists(), model.size_gb())];
        crate::downloads::ensure_free_space(need.iter().filter(|n| n.0).map(|n| n.1).sum())?;
        let http = crate::downloads::client();
        if !server_exe().exists() {
            let (file, _) = server_build();
            let url = format!("https://github.com/ggml-org/llama.cpp/releases/download/{LLAMA_BUILD}/{file}");
            // Keep the real name: its extension says how to unpack it.
            let archive = server_dir().parent().map(|d| d.join(&file)).context("no folder for the task AI")?;
            crate::downloads::fetch(&http, &url, &archive, crate::downloads::sha256_of(&file), |d, t| {
                on_progress("Downloading the task AI runner", if t > 0 { d as f64 / t as f64 * 100.0 } else { -1.0 })
            })
            .await?;
            // Only the server and its libraries (not the dozens of other tools).
            // (Other tools' libraries, like llama-cli-impl.dll, are skipped; tested: the
            // server runs without them. llama-common, ggml-* and the CPU variants are needed.)
            let keep = |n: &str| {
                let other_tool = n.contains("-impl.") && !n.starts_with("llama-server");
                !other_tool
                    && (n.starts_with("llama-server")
                        || [".dll", ".so", ".dylib", ".metal"].iter().any(|e| n.ends_with(e))
                        || n.contains(".so.")
                        || n.contains(".dylib"))
            };
            // Unpacked beside its folder, then moved in: llama-server being there
            // must mean every library is too.
            let staging = crate::downloads::staging(&server_dir());
            crate::downloads::unpack(&archive, &staging, keep)?;
            add_vc_runtime(self.redist.as_deref(), &staging);
            crate::downloads::commit(&staging, &server_dir())?;
            let _ = std::fs::remove_file(&archive);
        }
        let sha = crate::downloads::sha256_of(model.file());
        crate::downloads::fetch(&http, &model.url(), &model_path(model), sha, |d, t| {
            on_progress(&format!("Downloading {}", model.label()), if t > 0 { d as f64 / t as f64 * 100.0 } else { -1.0 })
        })
        .await?;
        on_progress("Ready", 100.0);
        Ok(())
    }

    /// Start (or restart, for a bigger context or another model) the server.
    async fn ensure_running(&self, settings: &Settings, ctx: u32) -> Result<u16> {
        let model = task_model(settings);
        let (exe, gguf) = (server_exe(), model_path(model));
        if !exe.exists() || !gguf.exists() {
            return Err(anyhow!("The task AI isn't downloaded yet. Open Settings → Setup to download it."));
        }
        {
            let mut guard = self.server.lock().unwrap();
            let reusable = guard.as_mut().is_some_and(|s| {
                matches!(s.child.try_wait(), Ok(None)) && s.ctx >= ctx && s.model == model && s.device == settings.device
            });
            if reusable {
                return Ok(guard.as_ref().unwrap().port);
            }
            stop(&mut guard);
            add_vc_runtime(self.redist.as_deref(), &server_dir());
            let port = free_port()?;
            let threads = crate::hardware::worker_threads();
            let mut cmd = std::process::Command::new(&exe);
            cmd.args(server_args(&gguf, port, ctx, &settings.device, threads))
                // The Windows builds use OpenMP (libomp.dll): the same thread cap,
                // and threads that sleep between jobs instead of spinning.
                .env("OMP_NUM_THREADS", threads.to_string())
                .env("OMP_WAIT_POLICY", "PASSIVE")
                .current_dir(server_dir())
                .stdin(std::process::Stdio::null())
                .stdout(std::process::Stdio::null())
                .stderr(std::process::Stdio::null());
            #[cfg(windows)]
            {
                use std::os::windows::process::CommandExt;
                cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
            }
            let child = cmd.spawn().context("could not start the task AI")?;
            end_with_voice_desk(&child);
            *guard = Some(Server { child, port, ctx, model, device: settings.device.clone() });
        }
        let port = self.server.lock().unwrap().as_ref().map(|s| s.port).unwrap_or_default();
        // Loading the model takes a few seconds (longer on the first run).
        for _ in 0..240 {
            tokio::time::sleep(Duration::from_millis(500)).await;
            let alive = self.server.lock().unwrap().as_mut().is_some_and(|s| matches!(s.child.try_wait(), Ok(None)));
            if !alive {
                stop(&mut self.server.lock().unwrap());
                return Err(anyhow!("The task AI stopped while starting (not enough memory?)"));
            }
            let health = self.http.get(format!("http://127.0.0.1:{port}/health")).timeout(Duration::from_secs(2)).send().await;
            if health.is_ok_and(|r| r.status().is_success()) {
                return Ok(port);
            }
        }
        stop(&mut self.server.lock().unwrap());
        Err(anyhow!("The task AI didn't start in time"))
    }

    /// Stop the server once it has been idle for IDLE_STOP. (A timer set by an
    /// earlier request must not stop it in the middle of a later one.)
    fn stop_when_idle(&self) {
        let n = self.used.fetch_add(1, Ordering::SeqCst) + 1;
        let (used, in_flight, server) = (self.used.clone(), self.in_flight.clone(), self.server.clone());
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(IDLE_STOP).await;
            // Checked under the server lock, which a new request takes to use the server.
            let mut guard = server.lock().unwrap();
            if unused_since(&in_flight, &used, n) {
                stop(&mut guard);
            }
        });
    }

    async fn chat(&self, settings: &Settings, system: &str, user: &str) -> Result<Value> {
        let _in_flight = InFlight::new(self);
        let port = self.ensure_running(settings, context_for(&format!("{system}{user}"))).await?;
        let body = json!({
            "messages": [
                { "role": "system", "content": system },
                { "role": "user", "content": user }
            ],
            "temperature": 0.1,
            // A confused model on a slow laptop could otherwise write until the context is full.
            "max_tokens": ANSWER_TOKENS,
            "response_format": { "type": "json_schema", "json_schema": { "name": "tasks", "schema": schema() } },
            "chat_template_kwargs": { "enable_thinking": false },
        });
        let resp = self.http.post(format!("http://127.0.0.1:{port}/v1/chat/completions")).json(&body).send().await?;
        let status = resp.status();
        let v: Value = resp.json().await?;
        if !status.is_success() {
            return Err(anyhow!("task AI error {status}: {}", v["error"]["message"].as_str().unwrap_or("unknown")));
        }
        let content = v["choices"][0]["message"]["content"].as_str().context("empty task AI response")?;
        serde_json::from_str(content).with_context(|| format!("task AI returned invalid JSON: {content}"))
    }

    pub async fn extract(
        &self,
        settings: &Settings,
        title: &str,
        segments: &[Segment],
        mode: Mode,
        on_progress: impl FnMut(usize, usize),
    ) -> Result<Extraction> {
        let _one_at_a_time = self.busy.lock().await;
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
    }

    #[test]
    fn server_follows_the_processor_setting() {
        let args = |d| server_args(std::path::Path::new("m.gguf"), 8080, 4096, d, 4).join(" ");
        assert!(args("cpu").ends_with("-ngl 0 --device none"));
        assert!(args("auto").ends_with("-ngl 99"));
        assert!(args("cpu").contains("-c 4096") && args("cpu").contains("-t 4") && args("cpu").contains("--cache-type-k q8_0"));
        // Prompt reading capped too, no spinning threads, few HTTP threads.
        assert!(args("cpu").contains("-tb 4 --poll 0 --threads-http 2"));
    }

    #[test]
    fn models_are_pinned_and_checked() {
        for m in [TaskModel::Small, TaskModel::Large] {
            assert!(!m.url().contains("/resolve/main/"), "{}", m.url());
            assert!(crate::downloads::sha256_of(m.file()).is_some(), "{}", m.file());
        }
        assert!(crate::downloads::sha256_of(&server_build().0).is_some(), "no SHA-256 for {}", server_build().0);
    }

    #[test]
    fn idle_timer_never_stops_a_request_in_flight() {
        let (in_flight, used) = (AtomicUsize::new(0), AtomicU64::new(0));
        let start = || {
            in_flight.fetch_add(1, Ordering::SeqCst);
            used.fetch_add(1, Ordering::SeqCst);
        };
        let end = || {
            in_flight.fetch_sub(1, Ordering::SeqCst);
            used.fetch_add(1, Ordering::SeqCst) + 1 // the timer this sets
        };
        start();
        let first_timer = end();
        start(); // a second request starts before the first timer fires
        assert!(!unused_since(&in_flight, &used, first_timer));
        let second_timer = end();
        assert!(!unused_since(&in_flight, &used, first_timer));
        assert!(unused_since(&in_flight, &used, second_timer));
    }

    #[test]
    fn task_model_by_ram() {
        assert_eq!(TaskModel::from_setting("auto", 4.0), TaskModel::Small);
        assert_eq!(TaskModel::from_setting("auto", 8.0), TaskModel::Large);
        assert_eq!(TaskModel::from_setting("auto", 15.4), TaskModel::Large);
        assert_eq!(TaskModel::from_setting("qwen3-1.7b", 32.0), TaskModel::Small);
        assert_eq!(TaskModel::from_setting("qwen3:4b", 4.0), TaskModel::Small); // old Ollama name: treated as auto
    }

    /// Downloads the server and model if needed (~1-2.5 GB once).
    async fn llm(settings: &Settings) -> Llm {
        let l = Llm::new(None);
        l.pull(settings, |_, _| {}).await.unwrap();
        l
    }

    fn test_model() -> String {
        std::env::var("VOICEDESK_LLM").unwrap_or_else(|_| "auto".into())
    }

    fn seg(start: f64, speaker: &str, text: &str) -> Segment {
        Segment { start, end: start + 4.0, speaker: speaker.into(), text: text.into(), words: None }
    }

    /// Needs the task AI (downloaded on first run). Run: cargo test llm -- --ignored --nocapture
    /// VOICEDESK_LLM=qwen3-1.7b or qwen3-4b picks the model (default: auto).
    #[tokio::test(flavor = "current_thread")]
    #[ignore]
    async fn extracts_only_my_tasks() {
        let settings = Settings { user_name: "Rajvee".into(), llm_model: test_model(), ..Settings::default() };
        let segments = vec![
            seg(0.0, "Speaker 1", "Okay let's get started. Quick updates on the launch."),
            seg(6.0, "Me", "The login page is done, I'm waiting on design review."),
            seg(12.0, "Speaker 1", "Great. Rajvee, can you send the quarterly report to Priya by Friday?"),
            seg(18.0, "Me", "Sure, I'll do that. I'll also fix the signup bug before tomorrow's standup."),
            seg(25.0, "Speaker 2", "I'll take care of the marketing email this week."),
            seg(31.0, "Speaker 1", "Thanks. Priya, please update the roadmap slide."),
        ];
        let e = llm(&settings).await.extract(&settings, "Launch sync", &segments, Mode::Meeting, |_, _| {}).await.unwrap();
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
        let settings = Settings { user_name: "Nishchay".into(), llm_model: test_model(), ..Settings::default() };
        let segments = vec![
            seg(0.0, "Speaker 1", "Hello, hello, good morning to everyone. Nishchay, you need to complete doing this task, which is eating an apple."),
            seg(9.5, "Speaker 1", "And Nishchay, I am giving you another task of playing games."),
        ];
        let e = llm(&settings).await.extract(&settings, "Test", &segments, Mode::Meeting, |_, _| {}).await.unwrap();
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
        let settings = Settings { user_name: "Nishchay".into(), llm_model: test_model(), ..Settings::default() };
        let segments = vec![seg(
            0.0,
            "Me",
            "I need to call the bank tomorrow morning and renew my passport next week. Also buy milk.",
        )];
        let e = llm(&settings).await.extract(&settings, "Notes", &segments, Mode::SelfNotes, |_, _| {}).await.unwrap();
        for t in &e.tasks {
            println!("- {} | by {:?} | due {:?}", t.description, t.assigned_by, t.due);
        }
        assert_eq!(e.tasks.len(), 3, "{:?}", e.tasks.iter().map(|t| &t.description).collect::<Vec<_>>());
    }
}
