//! Client for the Python speech engine sidecar (engine/engine.py).
//!
//! The process is spawned lazily and respawned whenever it isn't running (it
//! exits by itself after an idle period to free memory). Requests/responses
//! are JSON Lines matched by `id`; messages without an `id` (live dictation
//! results etc.) go to a global event handler.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{anyhow, Context, Result};
use serde_json::{json, Value};
use tokio::sync::oneshot;

pub type EventFn = Box<dyn Fn(&Value) + Send + Sync>;
type GlobalFn = Arc<dyn Fn(&Value) + Send + Sync>;

#[derive(Default)]
struct Pending {
    replies: HashMap<u64, oneshot::Sender<Result<Value>>>,
    events: HashMap<u64, EventFn>,
}

struct Proc {
    child: Child,
    stdin: ChildStdin,
}

pub struct Engine {
    python: PathBuf,
    script: PathBuf,
    proc: Mutex<Option<Proc>>,
    pending: Arc<Mutex<Pending>>,
    global: Mutex<Option<GlobalFn>>,
    next_id: AtomicU64,
}

pub type Reply = oneshot::Receiver<Result<Value>>;

impl Engine {
    pub fn new(python: PathBuf, script: PathBuf) -> Self {
        Self {
            python,
            script,
            proc: Mutex::new(None),
            pending: Arc::new(Mutex::new(Pending::default())),
            global: Mutex::new(None),
            next_id: AtomicU64::new(1),
        }
    }

    /// Handler for messages that aren't replies to a request (utterances, sleep notices...).
    pub fn on_global_event(&self, f: impl Fn(&Value) + Send + Sync + 'static) {
        *self.global.lock().unwrap() = Some(Arc::new(f));
    }

    /// The folder with engine.py and its requirements files.
    pub fn script_dir(&self) -> PathBuf {
        self.script.parent().map(PathBuf::from).unwrap_or_default()
    }

    pub fn is_installed(&self) -> bool {
        // Python set up on first run counts only once that setup finished.
        let first_run_python = self.python == crate::engine_setup::python_exe();
        self.python.exists() && self.script.exists() && (!first_run_python || crate::engine_setup::installed_packs(&self.script_dir()).is_some())
    }

    /// Optional packs in the first-run Python (None: not set up yet, or a development .venv).
    pub fn packs(&self) -> Option<crate::engine_setup::Packs> {
        (self.python == crate::engine_setup::python_exe()).then(|| crate::engine_setup::installed_packs(&self.script_dir())).flatten()
    }

    pub fn is_running(&self) -> bool {
        match self.proc.lock().unwrap().as_mut() {
            Some(p) => matches!(p.child.try_wait(), Ok(None)),
            None => false,
        }
    }

    /// The engine's process id while it runs (for its memory use).
    pub fn pid(&self) -> Option<u32> {
        self.proc.lock().unwrap().as_ref().map(|p| p.child.id())
    }

    fn spawn(&self) -> Result<Proc> {
        if !self.python.exists() {
            return Err(anyhow!(
                "Speech engine is not set up (missing {}). Open Settings → Setup to download it.",
                self.python.display()
            ));
        }
        let mut cmd = Command::new(&self.python);
        cmd.arg("-u")
            .arg(&self.script)
            .env("PYTHONIOENCODING", "utf-8")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        {
            use std::os::windows::process::CommandExt;
            const CREATE_NO_WINDOW: u32 = 0x0800_0000;
            cmd.creation_flags(CREATE_NO_WINDOW);
        }
        let mut child = cmd
            .spawn()
            .with_context(|| format!("failed to start speech engine with {}", self.python.display()))?;

        let stdout = child.stdout.take().context("engine stdout")?;
        let stderr = child.stderr.take().context("engine stderr")?;
        let stdin = child.stdin.take().context("engine stdin")?;

        let pending = self.pending.clone();
        let global = self.global.lock().unwrap().clone();
        std::thread::spawn(move || {
            for line in BufReader::new(stdout).lines() {
                let Ok(line) = line else { break };
                let Ok(msg) = serde_json::from_str::<Value>(&line) else {
                    eprintln!("[engine] non-JSON output: {line}");
                    continue;
                };
                let Some(id) = msg.get("id").and_then(Value::as_u64) else {
                    if let Some(g) = &global {
                        g(&msg);
                    }
                    continue;
                };
                // Model downloads show in the app's status whichever request caused them.
                if msg["event"] == "download" {
                    if let Some(g) = &global {
                        g(&msg);
                    }
                }
                let mut p = pending.lock().unwrap();
                if msg.get("event").is_some() {
                    if let Some(cb) = p.events.get(&id) {
                        cb(&msg);
                    }
                    continue;
                }
                p.events.remove(&id);
                if let Some(tx) = p.replies.remove(&id) {
                    let res = if msg["ok"].as_bool() == Some(true) {
                        Ok(msg["result"].clone())
                    } else {
                        Err(anyhow!("{}", msg["error"].as_str().unwrap_or("engine error")))
                    };
                    let _ = tx.send(res);
                }
            }
            // Process exited: fail everything still waiting.
            let mut p = pending.lock().unwrap();
            p.events.clear();
            for (_, tx) in p.replies.drain() {
                let _ = tx.send(Err(anyhow!("speech engine stopped unexpectedly")));
            }
            drop(p);
            if let Some(g) = &global {
                g(&json!({ "event": "exited" }));
            }
        });
        std::thread::spawn(move || {
            for line in BufReader::new(stderr).lines().map_while(Result::ok) {
                eprintln!("{line}");
            }
        });

        Ok(Proc { child, stdin })
    }

    /// Write one request line, starting the engine first if `wake` (else fail when it's asleep).
    fn write_line(&self, line: &str, wake: bool) -> Result<()> {
        let mut guard = self.proc.lock().unwrap();
        let alive = match guard.as_mut() {
            Some(p) => p.child.try_wait()?.is_none(),
            None => false,
        };
        if !alive {
            if !wake {
                return Err(anyhow!("speech engine not running"));
            }
            *guard = Some(self.spawn()?);
        }
        let p = guard.as_mut().unwrap();
        p.stdin.write_all(line.as_bytes())?;
        p.stdin.flush()?;
        Ok(())
    }

    /// Write a request now (preserving order with other writes) and return the reply receiver.
    pub fn start_request(&self, cmd: &str, args: Value, on_event: Option<EventFn>) -> Result<Reply> {
        self.begin(cmd, args, on_event, true)
    }

    fn begin(&self, cmd: &str, mut args: Value, on_event: Option<EventFn>, wake: bool) -> Result<Reply> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        args["id"] = json!(id);
        args["cmd"] = json!(cmd);
        let line = serde_json::to_string(&args)? + "\n";
        let (tx, rx) = oneshot::channel();
        {
            let mut p = self.pending.lock().unwrap();
            p.replies.insert(id, tx);
            if let Some(cb) = on_event {
                p.events.insert(id, cb);
            }
        }
        if let Err(e) = self.write_line(&line, wake) {
            let mut p = self.pending.lock().unwrap();
            p.replies.remove(&id);
            p.events.remove(&id);
            return Err(e);
        }
        Ok(rx)
    }

    pub async fn wait(rx: Reply) -> Result<Value> {
        rx.await.map_err(|_| anyhow!("speech engine reply dropped"))?
    }

    /// Send a command and wait for its result. `on_event` receives progress/warning events.
    pub async fn request(&self, cmd: &str, args: Value, on_event: Option<EventFn>) -> Result<Value> {
        Self::wait(self.start_request(cmd, args, on_event)?).await
    }

    /// Ask only if the engine is running: a sleeping engine stays asleep (starting
    /// it loads Python and ~0.5-1 GB of models just to answer).
    pub async fn request_if_running(&self, cmd: &str, args: Value) -> Result<Value> {
        Self::wait(self.begin(cmd, args, None, false)?).await
    }

    /// Fire-and-forget message (live audio). Never spawns the engine.
    pub fn send(&self, msg: &Value) -> Result<()> {
        let line = serde_json::to_string(msg)? + "\n";
        let mut guard = self.proc.lock().unwrap();
        let p = guard.as_mut().context("speech engine not running")?;
        p.stdin.write_all(line.as_bytes())?;
        Ok(())
    }

    pub fn shutdown(&self) {
        if let Some(mut p) = self.proc.lock().unwrap().take() {
            let _ = p.child.kill();
        }
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.shutdown();
    }
}
