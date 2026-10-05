//! First run on a friend's computer: the speech engine's Python and packages,
//! downloaded for this computer only (then everything works offline).
//!
//! - Python: a standalone build (~22-34 MB), unpacked into Voice Desk's folder.
//! - Packages: the core (~0.3 GB), plus optional packs where they help:
//!   NVIDIA speed-up (~2 GB) and Hindi/Gujarati (~0.7 GB).
//! - Models: the Whisper size this computer uses, voice ID, speaker detection.
//!
//! In development the project's `.venv` is used instead.

use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{anyhow, Context, Result};
use serde::{Deserialize, Serialize};

/// python-build-standalone release (pinned: the same Python everywhere).
const PYTHON_TAG: &str = "20260929";
const PYTHON_VERSION: &str = "3.12.14";

/// Optional extras, chosen in the setup screen.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize)]
pub struct Packs {
    /// NVIDIA GPU speed-up for Whisper (CUDA libraries, ~2 GB).
    pub nvidia: bool,
    /// Hindi/Gujarati written as spoken (PyTorch CPU, ~0.7 GB, plus its model on first use).
    pub indic: bool,
}

/// Voice Desk's own folder for the speech engine's Python.
pub fn runtime_dir() -> PathBuf {
    crate::system::voicedesk_models_dir().parent().map(|p| p.join("runtime")).unwrap_or_default()
}

/// Written last by `install`: Python unpacked but setup interrupted (packages
/// half installed, models missing) must not count as ready.
fn done_marker() -> PathBuf {
    runtime_dir().join("installed.json")
}

/// installed.json: the packs and the requirements they were installed from.
#[derive(Serialize, Deserialize)]
struct Installed {
    #[serde(flatten)]
    packs: Packs,
    /// requirements_hash() at install time ("" in setups from before it was kept).
    #[serde(default)]
    requirements: String,
}

/// The packs the last finished setup installed, whatever their requirements.
fn recorded() -> Option<Installed> {
    serde_json::from_slice(&std::fs::read(done_marker()).ok()?).ok()
}

/// The packs a finished setup installed; None until setup has finished, and
/// again after an app update ships different requirements (Settings then shows
/// "Getting ready", and running setup again upgrades the packages).
pub fn installed_packs(engine_dir: &Path) -> Option<Packs> {
    let r = recorded()?;
    (r.requirements == requirements_hash(engine_dir, r.packs)).then_some(r.packs)
}

/// SHA-256 over the requirement files that `packs` install from (and the pinned
/// versions in constraints.txt), as shipped with this version of the app.
fn requirements_hash(engine_dir: &Path, packs: Packs) -> String {
    use sha2::{Digest, Sha256};
    let mut h = Sha256::new();
    let files = [
        ("requirements.txt", true),
        ("requirements-nvidia.txt", packs.nvidia),
        ("requirements-indic.txt", packs.indic),
        ("constraints.txt", true),
    ];
    for (name, used) in files {
        if let (true, Ok(text)) = (used, std::fs::read(engine_dir.join(name))) {
            h.update(name.as_bytes());
            h.update([0]);
            h.update(&text);
        }
    }
    h.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Rough download + install sizes (GB), for the free-space check.
const PYTHON_GB: f64 = 0.05;
const CORE_GB: f64 = 0.4;
const NVIDIA_GB: f64 = 3.3;
const INDIC_GB: f64 = 1.7;
const SPEECH_MODELS_GB: f64 = 1.6;

pub fn python_exe() -> PathBuf {
    let base = runtime_dir().join("python");
    if cfg!(windows) {
        base.join("python.exe")
    } else {
        base.join("bin").join("python3")
    }
}

fn python_url() -> Result<String> {
    let triple = match (std::env::consts::OS, std::env::consts::ARCH) {
        ("windows", "x86_64") => "x86_64-pc-windows-msvc",
        ("macos", "aarch64") => "aarch64-apple-darwin",
        ("macos", "x86_64") => "x86_64-apple-darwin",
        ("linux", "x86_64") => "x86_64-unknown-linux-gnu",
        ("linux", "aarch64") => "aarch64-unknown-linux-gnu",
        (os, arch) => return Err(anyhow!("No ready-made Python for {os}/{arch}")),
    };
    Ok(format!(
        "https://github.com/astral-sh/python-build-standalone/releases/download/{PYTHON_TAG}/cpython-{PYTHON_VERSION}+{PYTHON_TAG}-{triple}-install_only_stripped.tar.gz"
    ))
}

fn quiet(cmd: &mut Command) -> &mut Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    cmd
}

/// Run a command, passing each output line to `on_line`; error with its last lines if it fails.
fn run(cmd: &mut Command, mut on_line: impl FnMut(&str)) -> Result<()> {
    let mut child = quiet(cmd).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn()?;
    let stderr = child.stderr.take().context("stderr")?;
    let errors = std::thread::spawn(move || {
        BufReader::new(stderr).lines().map_while(Result::ok).collect::<Vec<_>>()
    });
    for line in BufReader::new(child.stdout.take().context("stdout")?).lines().map_while(Result::ok) {
        on_line(&line);
    }
    let status = child.wait()?;
    let errors = errors.join().unwrap_or_default();
    if !status.success() {
        let tail = errors.iter().rev().take(3).rev().cloned().collect::<Vec<_>>().join(" / ");
        return Err(anyhow!("{tail}"));
    }
    Ok(())
}

/// pip's progress lines, shortened for the setup screen ("Downloading ctranslate2…").
fn pip_detail(line: &str) -> Option<String> {
    let l = line.trim();
    for prefix in ["Collecting ", "Downloading ", "Installing collected packages"] {
        if let Some(rest) = l.strip_prefix(prefix) {
            let token = rest.split([' ', '=', '<', '>', ';', '(']).next().unwrap_or("").rsplit('/').next().unwrap_or("");
            // A wheel file ("ctranslate2-4.6.0-cp312-...whl"): the name is before the version.
            let name = if token.contains(".whl") || token.contains(".tar.gz") { token.split('-').next().unwrap_or(token) } else { token };
            return Some(if prefix.starts_with("Installing") { "Installing packages…".into() } else { format!("Downloading {name}…") });
        }
    }
    None
}

/// A line `engine.py --prefetch` prints -> (percent of the whole setup, detail).
/// Its download events ({"event":"download","what","done_mb","total_mb"|null})
/// move the bar through 72-99%; other JSON is skipped; plain text is shown as is.
fn prefetch_line(line: &str) -> Option<(Option<f64>, String)> {
    let line = line.trim();
    if line.is_empty() {
        return None;
    }
    let Ok(ev) = serde_json::from_str::<serde_json::Value>(line) else {
        return Some((None, line.to_string()));
    };
    if ev["event"] != "download" {
        return None;
    }
    let what = ev["what"].as_str().unwrap_or("a model");
    let done = ev["done_mb"].as_f64().unwrap_or(0.0);
    Some(match ev["total_mb"].as_f64().filter(|t| *t > 0.0) {
        Some(total) => {
            let frac = (done / total).clamp(0.0, 1.0);
            (Some(72.0 + 27.0 * frac), format!("Downloading {what}… {:.0}%", frac * 100.0))
        }
        None => (None, format!("Downloading {what}… {done:.0} MB")),
    })
}

/// Set up the speech engine. `engine_dir` holds engine.py and the requirements
/// files. `progress(step, percent, detail)`.
pub async fn install(http: &reqwest::Client, engine_dir: &Path, packs: Packs, progress: impl Fn(&str, f64, &str) + Send + Sync + 'static) -> Result<()> {
    let progress = std::sync::Arc::new(progress);
    // Adding a pack later keeps the ones already installed.
    let before = recorded();
    let had = before.as_ref().map(|r| r.packs).unwrap_or_default();
    let packs = Packs { nvidia: packs.nvidia || had.nvidia, indic: packs.indic || had.indic };
    let need = [
        (!python_exe().exists(), PYTHON_GB),
        (before.is_none(), CORE_GB + SPEECH_MODELS_GB),
        (packs.nvidia && !had.nvidia, NVIDIA_GB),
        (packs.indic && !had.indic, INDIC_GB),
    ];
    crate::downloads::ensure_free_space(need.iter().filter(|n| n.0).map(|n| n.1).sum())?;
    // 1. Python
    if !python_exe().exists() {
        let url = python_url()?;
        let file = url.rsplit('/').next().unwrap_or("python.tar.gz");
        let archive = runtime_dir().join(file);
        let p = progress.clone();
        crate::downloads::fetch(http, &url, &archive, crate::downloads::sha256_of(file), move |d, t| {
            p("Downloading Python", if t > 0 { d as f64 / t as f64 * 10.0 } else { 0.0 }, "")
        })
        .await?;
        progress("Unpacking Python", 10.0, "");
        // Unpacked beside its place, then moved in: python.exe appearing is what
        // says Python is there, so a half-unpacked folder must never be "python/".
        let python_dir = runtime_dir().join("python");
        let staging = crate::downloads::staging(&python_dir);
        crate::downloads::extract_tree(&archive, &staging)?; // the archive's top folder is "python/"
        crate::downloads::commit(&staging.join("python"), &python_dir)?;
        let _ = std::fs::remove_dir_all(&staging);
        let _ = std::fs::remove_file(&archive);
        if !python_exe().exists() {
            return Err(anyhow!("Python didn't unpack where expected ({})", python_exe().display()));
        }
    }

    // 2. Packages (pip shows what it's doing; ~0.3 GB for the core)
    let python = python_exe();
    let mut steps: Vec<(&str, Vec<String>, f64, f64)> = vec![(
        "Installing the speech engine",
        vec!["-r".into(), engine_dir.join("requirements.txt").to_string_lossy().into()],
        12.0,
        if packs.nvidia || packs.indic { 45.0 } else { 70.0 },
    )];
    if packs.nvidia {
        steps.push((
            "Adding NVIDIA speed-up",
            vec!["-r".into(), engine_dir.join("requirements-nvidia.txt").to_string_lossy().into()],
            45.0,
            if packs.indic { 60.0 } else { 70.0 },
        ));
    }
    if packs.indic {
        steps.push((
            "Adding Hindi/Gujarati",
            vec![
                "-r".into(),
                engine_dir.join("requirements-indic.txt").to_string_lossy().into(),
                "--index-url".into(),
                "https://download.pytorch.org/whl/cpu".into(),
                "--extra-index-url".into(),
                "https://pypi.org/simple".into(),
            ],
            60.0,
            70.0,
        ));
    }
    // Exact versions (tested together) when the app ships them.
    let constraints = engine_dir.join("constraints.txt");
    let pin: Vec<String> = if constraints.exists() {
        vec!["-c".into(), constraints.to_string_lossy().into()]
    } else {
        Vec::new()
    };
    for (step, mut args, from, _to) in steps {
        args.extend(pin.iter().cloned());
        let (p, python, step) = (progress.clone(), python.clone(), step.to_string());
        p(&step, from, "");
        tauri::async_runtime::spawn_blocking(move || {
            run(
                Command::new(&python)
                    .args(["-m", "pip", "install", "--disable-pip-version-check", "--no-warn-script-location", "--progress-bar", "off"])
                    .args(&args),
                |line| {
                    if let Some(d) = pip_detail(line) {
                        p(&step, from, &d);
                    }
                },
            )
        })
        .await??;
    }

    // 3. Models for this computer (Whisper size, voice ID, speaker detection)
    let (p, python, script) = (progress.clone(), python.clone(), engine_dir.join("engine.py"));
    p("Downloading speech models", 72.0, "");
    tauri::async_runtime::spawn_blocking(move || {
        let mut pct = 72.0;
        run(Command::new(&python).arg(&script).arg("--prefetch").env("PYTHONIOENCODING", "utf-8"), |line| {
            if let Some((at, detail)) = prefetch_line(line) {
                pct = at.unwrap_or(pct);
                p("Downloading speech models", pct, &detail);
            }
        })
    })
    .await??;
    let done = Installed { packs, requirements: requirements_hash(engine_dir, packs) };
    std::fs::write(done_marker(), serde_json::to_vec(&done)?)?;
    progress("Ready", 100.0, "");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pip_lines_become_short_progress() {
        assert_eq!(pip_detail("Collecting faster-whisper>=1.2 (from -r req.txt (line 6))").as_deref(), Some("Downloading faster-whisper…"));
        assert_eq!(
            pip_detail("  Downloading ctranslate2-4.6.0-cp312-cp312-win_amd64.whl (19.4 MB)").as_deref(),
            Some("Downloading ctranslate2…")
        );
        assert_eq!(pip_detail("Installing collected packages: numpy, onnxruntime").as_deref(), Some("Installing packages…"));
        assert_eq!(pip_detail("Requirement already satisfied: numpy"), None);
    }

    #[test]
    fn python_for_this_computer() {
        let url = python_url().unwrap();
        assert!(url.contains(PYTHON_TAG) && url.ends_with("install_only_stripped.tar.gz"), "{url}");
        assert!(crate::downloads::sha256_of(url.rsplit('/').next().unwrap()).is_some(), "no SHA-256 for {url}");
    }

    #[test]
    fn prefetch_progress_lines() {
        let (pct, detail) =
            prefetch_line(r#"{"event":"download","what":"Speech model large-v3-turbo","done_mb":800.0,"total_mb":1600.0}"#).unwrap();
        assert_eq!((pct, detail.as_str()), (Some(85.5), "Downloading Speech model large-v3-turbo… 50%"));
        let (pct, detail) = prefetch_line(r#"{"event":"download","what":"Voice ID","done_mb":12.3,"total_mb":null}"#).unwrap();
        assert_eq!((pct, detail.as_str()), (None, "Downloading Voice ID… 12 MB"));
        assert_eq!(prefetch_line(r#"{"event":"ready"}"#), None);
        assert_eq!(prefetch_line("  "), None);
        assert_eq!(prefetch_line("loading voice ID").unwrap(), (None, "loading voice ID".to_string()));
    }

    #[test]
    fn requirements_changes_need_setup_again() {
        let dir = std::env::temp_dir().join(format!("vd-req-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("requirements.txt"), "numpy\n").unwrap();
        let (core, nv) = (Packs::default(), Packs { nvidia: true, indic: false });
        let a = requirements_hash(&dir, core);
        assert_eq!(a, requirements_hash(&dir, nv), "no NVIDIA file yet: same inputs");
        std::fs::write(dir.join("requirements-nvidia.txt"), "nvidia-cublas-cu12\n").unwrap();
        assert_eq!(a, requirements_hash(&dir, core), "a pack that isn't installed doesn't count");
        assert_ne!(a, requirements_hash(&dir, nv));
        std::fs::write(dir.join("constraints.txt"), "numpy==2.3.4\n").unwrap();
        assert_ne!(a, requirements_hash(&dir, core), "new pinned versions: install again");
        // Setups from before the hash was kept: packs read, no hash (so not installed).
        let old: Installed = serde_json::from_str(r#"{"nvidia":true,"indic":false}"#).unwrap();
        assert!(old.packs.nvidia && old.requirements.is_empty());
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod live {
    /// The whole first run, for real (~0.3 GB + models; into %LOCALAPPDATA%\VoiceDesk\runtime):
    /// `cargo test first_run_live -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn first_run_live() {
        let engine_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).parent().unwrap().join("engine");
        let t = std::time::Instant::now();
        let last = std::sync::Mutex::new(String::new());
        super::install(&crate::downloads::client(), &engine_dir, super::Packs::default(), move |step, pct, detail| {
            let line = format!("{pct:5.1}% {step} {detail}");
            let mut l = last.lock().unwrap();
            if *l != line {
                println!("{line}");
                *l = line;
            }
        })
        .await
        .unwrap();
        println!("done in {:.0}s; python at {}", t.elapsed().as_secs_f64(), super::python_exe().display());
        assert!(super::python_exe().exists());
    }
}
