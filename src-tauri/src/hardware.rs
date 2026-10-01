//! What this computer has, and how much of it Voice Desk is using.
//!
//! Voice Desk runs on laptops from 8 GB of RAM with no NVIDIA GPU up to
//! gaming PCs, so the device and thread choices are made from what's here.

use std::process::Command;

use serde::Serialize;
use sysinfo::{Pid, ProcessesToUpdate, System};

#[derive(Debug, Clone, Serialize)]
pub struct Gpu {
    /// CUDA device number ("cuda:0").
    pub index: u32,
    pub name: String,
    pub total_gb: f64,
    pub free_gb: f64,
}

#[derive(Serialize)]
pub struct Hardware {
    pub gpus: Vec<Gpu>,
    pub ram_total_gb: f64,
    pub ram_free_gb: f64,
    pub cores: usize,
    /// CPU threads Voice Desk's heavy work may use (half the cores).
    pub threads: usize,
}

fn quiet(cmd: &mut Command) -> &mut Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    cmd
}

/// NVIDIA GPUs (the only kind the speech and task models can use), with free memory.
pub fn gpus() -> Vec<Gpu> {
    let out = quiet(Command::new("nvidia-smi").args([
        "--query-gpu=index,name,memory.total,memory.free",
        "--format=csv,noheader,nounits",
    ]))
    .output();
    let Ok(out) = out else { return Vec::new() };
    parse_gpus(&String::from_utf8_lossy(&out.stdout))
}

fn parse_gpus(csv: &str) -> Vec<Gpu> {
    csv.lines()
        .filter_map(|line| {
            let f: Vec<&str> = line.split(',').map(str::trim).collect();
            if f.len() < 4 {
                return None;
            }
            Some(Gpu {
                index: f[0].parse().ok()?,
                name: f[1].to_string(),
                total_gb: f[2].parse::<f64>().ok()? / 1024.0,
                free_gb: f[3].parse::<f64>().ok()? / 1024.0,
            })
        })
        .collect()
}

pub fn cores() -> usize {
    System::physical_core_count().unwrap_or_else(|| std::thread::available_parallelism().map_or(4, |n| n.get()))
}

/// Threads for transcription and the task AI: half the cores, so the computer
/// stays responsive while a meeting is processed (and at least 2).
pub fn worker_threads() -> usize {
    (cores() / 2).max(2)
}

pub fn info() -> Hardware {
    let mut sys = System::new();
    sys.refresh_memory();
    Hardware {
        gpus: gpus(),
        ram_total_gb: sys.total_memory() as f64 / 1e9,
        ram_free_gb: sys.available_memory() as f64 / 1e9,
        cores: cores(),
        threads: worker_threads(),
    }
}

#[derive(Serialize)]
pub struct Usage {
    /// The app itself (window, audio capture).
    pub app_gb: f64,
    /// Speech engine, plus speaker detection while it runs.
    pub speech_gb: f64,
    /// Ollama and its model, while loaded.
    pub task_ai_gb: f64,
    /// Whole GPU memory in use (Windows doesn't report it per app), if there's an NVIDIA GPU.
    pub gpu_used_gb: Option<f64>,
    pub gpu_total_gb: Option<f64>,
}

/// RAM in use right now by Voice Desk's parts.
pub fn usage() -> Usage {
    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);
    let me = Pid::from_u32(std::process::id());
    let mem = |pid: Pid| sys.process(pid).map_or(0, |p| p.memory());
    // Descendants of the app: the speech engine, its speaker-detection helper, and an Ollama we started.
    let is_below = |mut pid: Pid| {
        while let Some(parent) = sys.process(pid).and_then(|p| p.parent()) {
            if parent == me {
                return true;
            }
            pid = parent;
        }
        false
    };
    let (mut speech, mut ai) = (0u64, 0u64);
    for (pid, p) in sys.processes() {
        let name = p.name().to_string_lossy().to_lowercase();
        if name.contains("ollama") {
            ai += p.memory();
        } else if *pid != me && is_below(*pid) {
            speech += p.memory();
        }
    }
    let gpu = gpus();
    let gb = |b: u64| b as f64 / 1e9;
    Usage {
        app_gb: gb(mem(me)),
        speech_gb: gb(speech),
        task_ai_gb: gb(ai),
        gpu_used_gb: (!gpu.is_empty()).then(|| gpu.iter().map(|g| g.total_gb - g.free_gb).sum()),
        gpu_total_gb: (!gpu.is_empty()).then(|| gpu.iter().map(|g| g.total_gb).sum()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_nvidia_smi() {
        let g = parse_gpus("0, NVIDIA GeForce RTX 3050 Laptop GPU, 4096, 3900\n1, Tesla T4, 15360, 15000\n");
        assert_eq!(g.len(), 2);
        assert_eq!((g[0].index, g[0].name.as_str()), (0, "NVIDIA GeForce RTX 3050 Laptop GPU"));
        assert!((g[0].total_gb - 4.0).abs() < 1e-9);
        assert!(parse_gpus("").is_empty());
        assert!(parse_gpus("NVIDIA-SMI has failed").is_empty());
    }
}
