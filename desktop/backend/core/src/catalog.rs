//! The speech and task models Voice Desk offers, what each needs and uses,
//! and which of them this computer can run.
//!
//! Measured 2026-10-05 on a Ryzen 7 5800H with an RTX 3050 Laptop 4 GB: speech
//! on 36 s of speech, the task AI on one meeting-sized request (~3 KB of
//! transcript). RAM is the peak, loading included.

use serde::Serialize;

use crate::db::Settings;
use crate::hardware::Hardware;
use crate::llm::TaskModel;

/// What a model uses while working.
#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
pub struct Use {
    pub ram_gb: f64,
    /// GPU memory; 0 on the CPU.
    pub gpu_gb: f64,
    /// Busy CPU cores while working.
    pub cores: f64,
    /// Seconds of work per minute of speech (speech models) or per meeting (task models).
    pub speed_s: f64,
}

pub struct ModelSpec {
    pub id: &'static str,
    pub download_gb: f64,
    /// On an NVIDIA GPU. None: not offered there.
    pub gpu: Option<Use>,
    /// On the CPU, for computers with at least `min_ram_gb`. None: too slow there.
    pub cpu: Option<(Use, f64)>,
    /// Whisper on the CPU keeps to the threads Voice Desk allows (half the cores);
    /// llama-server measured ~8 cores with `-t 4`, so its figure isn't capped.
    pub capped: bool,
    /// How a downloaded copy is named: the Hugging Face folder's ending, or the file.
    pub file: &'static str,
}

const fn uses(ram_gb: f64, gpu_gb: f64, cores: f64, speed_s: f64) -> Use {
    Use { ram_gb, gpu_gb, cores, speed_s }
}

/// GPU memory left free for the task AI and other apps (as the engine's GPU_SPARE_GB).
const GPU_SPARE_GB: f64 = 0.3;

pub const SPEECH_MODELS: &[ModelSpec] = &[
    ModelSpec { id: "large-v3-turbo", download_gb: 1.6, gpu: Some(uses(1.7, 1.3, 1.0, 10.0)), cpu: None, capped: true, file: "faster-whisper-large-v3-turbo" },
    ModelSpec { id: "medium", download_gb: 1.5, gpu: Some(uses(1.6, 1.2, 1.0, 15.0)), cpu: None, capped: true, file: "faster-whisper-medium" },
    ModelSpec { id: "large-v3", download_gb: 2.9, gpu: Some(uses(3.2, 2.3, 1.0, 29.0)), cpu: None, capped: true, file: "faster-whisper-large-v3" },
    ModelSpec {
        id: "small",
        download_gb: 0.46,
        gpu: Some(uses(0.7, 0.5, 1.0, 7.0)),
        cpu: Some((uses(0.7, 0.0, 4.0, 19.0), 6.0)),
        capped: true,
        file: "faster-whisper-small",
    },
    ModelSpec { id: "base", download_gb: 0.14, gpu: None, cpu: Some((uses(0.3, 0.0, 3.5, 7.0), 0.0)), capped: true, file: "faster-whisper-base" },
];

pub const TASK_MODELS: &[ModelSpec] = &[
    ModelSpec {
        id: "qwen3-4b",
        download_gb: 2.5,
        gpu: Some(uses(2.6, 2.7, 1.0, 26.0)),
        cpu: Some((uses(3.7, 0.0, 8.0, 48.0), 6.0)),
        capped: false,
        file: "Qwen3-4B-Q4_K_M.gguf",
    },
    ModelSpec {
        id: "qwen3-1.7b",
        download_gb: 1.1,
        gpu: Some(uses(1.3, 1.3, 1.0, 16.0)),
        cpu: Some((uses(2.1, 0.0, 8.0, 21.0), 0.0)),
        capped: false,
        file: "Qwen3-1.7B-Q4_K_M.gguf",
    },
];

pub fn task_spec(id: &str) -> &'static ModelSpec {
    TASK_MODELS.iter().find(|m| m.id == id).expect("a task model in the catalog")
}

/// Where a model runs on this computer.
#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
pub struct Fit {
    /// "gpu" or "cpu".
    pub on: &'static str,
    #[serde(flatten)]
    pub uses: Use,
}

/// Why a model isn't offered on this computer.
#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
#[serde(tag = "needs", rename_all = "snake_case")]
pub enum NotOffered {
    /// An NVIDIA GPU with this much memory.
    Gpu { gb: f64 },
    /// The NVIDIA speed-up pack (speech on an NVIDIA GPU).
    NvidiaPack,
    /// This much RAM.
    Ram { gb: f64 },
}

/// Where a model would run here, or None if it can't run well. `nvidia_ready`:
/// Whisper can use an NVIDIA GPU only with the NVIDIA pack (the task AI uses
/// the GPU through Vulkan and needs no pack).
pub fn fit(spec: &ModelSpec, hw: &Hardware, device: &str, nvidia_ready: bool) -> Option<Fit> {
    let gpu_gb = hw
        .gpus
        .iter()
        .filter(|g| device == "auto" || device == "cuda" || device == format!("cuda:{}", g.index))
        .map(|g| g.total_gb)
        .fold(0.0, f64::max);
    if let Some(gpu) = spec.gpu.filter(|g| device != "cpu" && nvidia_ready && gpu_gb >= g.gpu_gb + GPU_SPARE_GB) {
        return Some(Fit { on: "gpu", uses: gpu });
    }
    let (cpu, _) = spec.cpu.filter(|(_, min_ram)| hw.ram_total_gb >= *min_ram)?;
    let cores = cpu.cores.min(if spec.capped { hw.threads } else { hw.cores } as f64);
    Some(Fit { on: "cpu", uses: Use { cores, ..cpu } })
}

/// Why a model isn't offered on this computer.
pub fn not_offered(spec: &ModelSpec, nvidia_ready: bool) -> NotOffered {
    match (spec.cpu, spec.gpu) {
        (None, Some(gpu)) if nvidia_ready => NotOffered::Gpu { gb: ((gpu.gpu_gb + GPU_SPARE_GB) * 100.0).round() / 100.0 },
        (None, Some(_)) => NotOffered::NvidiaPack,
        (cpu, _) => NotOffered::Ram { gb: cpu.map_or(0.0, |c| c.1) },
    }
}

/// A model as Settings offers it.
#[derive(Debug, Serialize)]
pub struct ModelOption {
    pub id: &'static str,
    pub download_gb: f64,
    pub downloaded: bool,
    /// Where it runs here; None when it isn't offered on this computer.
    pub fit: Option<Fit>,
    pub not_offered: Option<NotOffered>,
}

#[derive(Debug, Serialize)]
pub struct ModelOptions {
    pub speech: Vec<ModelOption>,
    pub task: Vec<ModelOption>,
    /// What the pickers show chosen: a model id, or "auto". A speech model this
    /// computer can't run counts as Auto (the engine falls back); the task AI
    /// runs the model chosen.
    pub speech_selected: String,
    pub task_selected: String,
    /// The task model Auto means on this computer.
    pub task_auto: &'static str,
    /// The task model these settings run (the chosen one, or Auto's).
    pub task_chosen: &'static str,
    /// The Hindi/Gujarati model, downloaded when first used.
    pub indic_model_gb: f64,
}

fn options(models: &'static [ModelSpec], hw: &Hardware, device: &str, nvidia_ready: bool, downloaded: &dyn Fn(&ModelSpec) -> bool) -> Vec<ModelOption> {
    models
        .iter()
        .map(|m| {
            let fit = fit(m, hw, device, nvidia_ready);
            ModelOption {
                id: m.id,
                download_gb: m.download_gb,
                downloaded: downloaded(m),
                fit,
                not_offered: fit.is_none().then(|| not_offered(m, nvidia_ready)),
            }
        })
        .collect()
}

/// The models Settings offers for `draft` (the settings on screen, maybe not
/// saved yet). `nvidia_ready`: the speech engine has the NVIDIA pack.
pub fn model_options(draft: &Settings, hw: &Hardware, nvidia_ready: bool) -> ModelOptions {
    let speech_dir = crate::paths::speech_models_dir();
    let speech_downloaded = |m: &ModelSpec| {
        std::fs::read_dir(&speech_dir)
            .into_iter()
            .flatten()
            .flatten()
            .any(|e| e.file_name().to_string_lossy().ends_with(m.file))
    };
    let task_downloaded = |m: &ModelSpec| crate::paths::voicedesk_models_dir().join(m.file).exists();
    let speech = options(SPEECH_MODELS, hw, &draft.device, nvidia_ready, &speech_downloaded);
    let task = options(TASK_MODELS, hw, &draft.device, true, &task_downloaded);
    let speech_selected = speech.iter().find(|m| m.id == draft.whisper_model && m.fit.is_some()).map_or("auto", |m| m.id);
    let task_selected = task.iter().find(|m| m.id == draft.llm_model).map_or("auto", |m| m.id);
    ModelOptions {
        speech_selected: speech_selected.into(),
        task_selected: task_selected.into(),
        speech,
        task,
        task_auto: TaskModel::from_setting("auto", hw.ram_total_gb).id(),
        task_chosen: TaskModel::from_setting(&draft.llm_model, hw.ram_total_gb).id(),
        indic_model_gb: crate::setup::INDIC_MODEL_GB,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::hardware::Gpu;

    fn hw(gpu_gb: Option<f64>, ram_gb: f64) -> Hardware {
        Hardware {
            gpus: gpu_gb.map(|g| Gpu { index: 0, name: "GPU".into(), total_gb: g, free_gb: g }).into_iter().collect(),
            ram_total_gb: ram_gb,
            ram_free_gb: ram_gb,
            cores: 8,
            threads: 4,
        }
    }

    fn spec(id: &str) -> &'static ModelSpec {
        SPEECH_MODELS.iter().chain(TASK_MODELS).find(|m| m.id == id).unwrap()
    }

    #[test]
    fn big_models_need_a_gpu_with_room() {
        let laptop = hw(Some(4.0), 16.0);
        assert_eq!(fit(spec("large-v3"), &laptop, "auto", true).map(|f| f.on), Some("gpu"));
        // 2.3 GB + 0.3 GB spare doesn't fit on a 2 GB card, and there's no CPU version.
        assert_eq!(fit(spec("large-v3"), &hw(Some(2.0), 16.0), "auto", true), None);
        assert_eq!(not_offered(spec("large-v3"), true), NotOffered::Gpu { gb: 2.6 });
        // Without the NVIDIA pack Whisper can't use the GPU at all.
        assert_eq!(fit(spec("large-v3"), &laptop, "auto", false), None);
        assert_eq!(not_offered(spec("large-v3"), false), NotOffered::NvidiaPack);
        // "CPU only" keeps everything on the CPU.
        assert_eq!(fit(spec("small"), &laptop, "cpu", true).map(|f| f.on), Some("cpu"));
    }

    #[test]
    fn cpu_models_need_enough_ram_and_keep_to_the_allowed_threads() {
        let small_pc = hw(None, 4.0);
        assert_eq!(fit(spec("small"), &small_pc, "auto", true), None);
        assert_eq!(not_offered(spec("small"), true), NotOffered::Ram { gb: 6.0 });
        let base = fit(spec("base"), &small_pc, "auto", true).unwrap();
        assert_eq!((base.on, base.uses.cores), ("cpu", 3.5));
        let small = fit(spec("small"), &hw(None, 8.0), "auto", true).unwrap();
        assert_eq!(small.uses.cores, 4.0, "capped to Voice Desk's threads");
        let qwen = fit(spec("qwen3-4b"), &hw(None, 8.0), "auto", true).unwrap();
        assert_eq!(qwen.uses.cores, 8.0, "llama-server isn't capped");
    }

    #[test]
    fn the_task_model_auto_means_follows_the_ram() {
        let mut s = Settings::default();
        assert_eq!(model_options(&s, &hw(None, 16.0), true).task_auto, "qwen3-4b");
        assert_eq!(model_options(&s, &hw(None, 4.0), true).task_chosen, "qwen3-1.7b");
        // A chosen model is the one that runs, and shows as chosen, even where it isn't offered.
        s.llm_model = "qwen3-4b".into();
        let o = model_options(&s, &hw(None, 4.0), true);
        assert_eq!((o.task_chosen, o.task_selected.as_str()), ("qwen3-4b", "qwen3-4b"));
        assert!(o.task[0].fit.is_none());
        // A speech model this computer can't run counts as Auto.
        s.whisper_model = "large-v3".into();
        assert_eq!(model_options(&s, &hw(None, 16.0), true).speech_selected, "auto");
        assert_eq!(model_options(&s, &hw(Some(4.0), 16.0), true).speech_selected, "large-v3");
    }
}
