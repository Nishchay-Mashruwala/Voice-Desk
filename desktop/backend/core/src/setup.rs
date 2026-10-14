//! First run on a new computer: what it still needs downloaded for the
//! settings, how big that is, and which packs to install.

use serde::{Deserialize, Serialize};

use crate::db::Settings;
use crate::engine_setup::Packs;
use crate::Backend;

/// What first-run setup downloads (GB), as the engine installer fetches it:
/// the speech engine itself, then either the NVIDIA (CUDA) or the CPU runtime
/// with a starter speech model, and the Hindi/Gujarati pack (what shrinks its
/// model to int8; no PyTorch). Disk space needed is in engine_setup.rs.
pub const ENGINE_BASE_GB: f64 = 0.4;
pub const ENGINE_NVIDIA_GB: f64 = 3.3;
pub const ENGINE_CPU_GB: f64 = 0.5;
pub const INDIC_PACK_GB: f64 = 0.03;
/// The Hindi/Gujarati model (IndicConformer), downloaded when first used and
/// then kept as a 1.0 GB int8 copy.
pub const INDIC_MODEL_GB: f64 = 2.4;
/// The task AI's runtime (llama-server), downloaded with its first model.
pub const TASK_RUNTIME_GB: f64 = 0.03;
/// The NVIDIA pack is offered on GPUs with at least this much memory: smaller
/// ones can't hold a useful speech model next to the task AI.
const NVIDIA_MIN_GPU_GB: f64 = 3.0;

/// The setup screen's checkboxes.
#[derive(Debug, Clone, Copy, Deserialize)]
pub struct Choices {
    /// Use the NVIDIA GPU for speech (when offered).
    pub nvidia: bool,
    /// Hindi/Gujarati written as spoken (when offered).
    pub indic: bool,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct Step {
    /// "engine" (download it), "engine_finish" (it's here, its setup didn't
    /// finish: only what's missing is fetched), "indic" (the Hindi/Gujarati pack
    /// for an engine set up without it) or "task_ai".
    pub kind: &'static str,
    pub gb: f64,
    /// The task model ("task_ai").
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<&'static str>,
    /// Downloaded later, when first used ("indic": its model).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub later_gb: Option<f64>,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct IndicOffer {
    /// The pack, downloaded now.
    pub extra_gb: f64,
    /// Its model, downloaded when first used.
    pub model_gb: f64,
}

#[derive(Debug, Serialize, PartialEq)]
pub struct SetupPlan {
    pub steps: Vec<Step>,
    pub total_gb: f64,
    /// Offer the NVIDIA speed-up: how much more it downloads. None: not offered here.
    pub offer_nvidia: Option<f64>,
    pub offer_indic: Option<IndicOffer>,
    /// Hindi/Gujarati are chosen: their model is used (it needs a Hugging Face token).
    pub uses_indic_model: bool,
    /// ...and that token isn't set.
    pub needs_hf_token: bool,
}

fn round2(gb: f64) -> f64 {
    (gb * 100.0).round() / 100.0
}

/// Hindi or Gujarati is among the languages.
pub fn indic_chosen(s: &Settings) -> bool {
    s.langs().iter().any(|l| l == "hi" || l == "gu")
}

/// This computer has a GPU worth the NVIDIA pack.
pub fn big_gpu(gpus: &[crate::hardware::Gpu]) -> bool {
    gpus.iter().any(|g| g.total_gb >= NVIDIA_MIN_GPU_GB)
}

/// Where the speech engine's setup is.
#[derive(Debug, Clone, Copy)]
pub struct EngineState {
    pub installed: bool,
    /// On this computer, but its setup didn't finish.
    pub partial: bool,
    /// Packs of a first-run engine (None: not set up, or a development .venv).
    pub packs: Option<Packs>,
}

impl EngineState {
    pub fn of(b: &Backend) -> Self {
        Self { installed: b.engine.is_installed(), partial: b.engine.is_partly_installed(), packs: b.engine.packs() }
    }
}

/// The packs to install for `settings`, or None when the engine needs nothing.
pub fn engine_packs(engine: EngineState, settings: &Settings, choices: Choices, big_gpu: bool) -> Option<Packs> {
    let indic = indic_chosen(settings);
    if !engine.installed {
        // Finishing keeps the packs already on disk (and adds Hindi/Gujarati if chosen).
        return Some(if engine.partial {
            Packs { nvidia: false, indic }
        } else {
            Packs { nvidia: choices.nvidia && big_gpu, indic: choices.indic && indic }
        });
    }
    // Chosen after first-run setup: add the pack (keeping the ones installed).
    engine.packs.filter(|p| indic && !p.indic).map(|_| Packs { nvidia: false, indic: true })
}

/// What setup would download for `draft` (the settings on screen, maybe not
/// saved yet) with these choices. `task`: (runtime downloaded, model
/// downloaded, model id, model size) for the draft's task model.
pub fn plan(engine: EngineState, draft: &Settings, choices: Choices, big_gpu: bool, task: (bool, bool, &'static str, f64)) -> SetupPlan {
    let indic = indic_chosen(draft);
    let fresh = !engine.installed && !engine.partial;
    let mut steps = Vec::new();
    if fresh {
        let runtime = if choices.nvidia && big_gpu { ENGINE_NVIDIA_GB } else { ENGINE_CPU_GB };
        let pack = if choices.indic && indic { INDIC_PACK_GB } else { 0.0 };
        steps.push(Step { kind: "engine", gb: round2(ENGINE_BASE_GB + runtime + pack), model: None, later_gb: None });
    } else if engine_packs(engine, draft, choices, big_gpu).is_some() {
        steps.push(if engine.installed {
            Step { kind: "indic", gb: INDIC_PACK_GB, model: None, later_gb: Some(INDIC_MODEL_GB) }
        } else {
            Step { kind: "engine_finish", gb: 0.0, model: None, later_gb: None }
        });
    }
    let (runtime_ready, model_ready, model, model_gb) = task;
    if !(runtime_ready && model_ready) {
        let gb = (if model_ready { 0.0 } else { model_gb }) + if runtime_ready { 0.0 } else { TASK_RUNTIME_GB };
        steps.push(Step { kind: "task_ai", gb: round2(gb), model: Some(model), later_gb: None });
    }
    let total = steps.iter().map(|s| s.gb).sum::<f64>();
    SetupPlan {
        total_gb: round2(total),
        steps,
        offer_nvidia: (fresh && big_gpu).then_some(round2(ENGINE_NVIDIA_GB - ENGINE_CPU_GB)),
        offer_indic: (fresh && indic).then_some(IndicOffer { extra_gb: INDIC_PACK_GB, model_gb: INDIC_MODEL_GB }),
        uses_indic_model: indic,
        needs_hf_token: indic && draft.hf_token.trim().is_empty(),
    }
}

/// `plan` for the backend's current state.
pub fn plan_for(b: &Backend, draft: &Settings, choices: Choices, big_gpu: bool) -> SetupPlan {
    let llm = b.llm.status(draft);
    let model = crate::llm::task_model(draft);
    plan(EngineState::of(b), draft, choices, big_gpu, (llm.installed, llm.model_ready, model.id(), model.size_gb()))
}

#[cfg(test)]
mod tests {
    use super::*;

    const YES: Choices = Choices { nvidia: true, indic: true };
    const NEW: EngineState = EngineState { installed: false, partial: false, packs: None };
    const TASK_MISSING: (bool, bool, &str, f64) = (false, false, "qwen3-4b", 2.5);
    const TASK_READY: (bool, bool, &str, f64) = (true, true, "qwen3-4b", 2.5);

    fn settings(langs: &[&str]) -> Settings {
        Settings { languages: langs.iter().map(|l| l.to_string()).collect(), ..Settings::default() }
    }

    #[test]
    fn a_new_computer_downloads_the_engine_and_the_task_ai() {
        let p = plan(NEW, &settings(&["en"]), YES, true, TASK_MISSING);
        assert_eq!(p.steps.iter().map(|s| (s.kind, s.gb)).collect::<Vec<_>>(), [("engine", 3.7), ("task_ai", 2.53)]);
        assert_eq!((p.total_gb, p.offer_nvidia), (6.23, Some(2.8)));
        assert_eq!(p.offer_indic, None, "Hindi/Gujarati not chosen");
        // Without a big GPU: the CPU runtime, and no NVIDIA offer.
        let p = plan(NEW, &settings(&["en", "gu"]), YES, false, TASK_READY);
        assert_eq!((p.steps[0].gb, p.offer_nvidia), (0.93, None));
        assert_eq!(p.offer_indic, Some(IndicOffer { extra_gb: 0.03, model_gb: 2.4 }));
    }

    #[test]
    fn an_engine_already_here_only_finishes_or_adds_the_pack() {
        let partial = EngineState { installed: false, partial: true, packs: None };
        let p = plan(partial, &settings(&["en"]), YES, true, TASK_READY);
        assert_eq!(p.steps, [Step { kind: "engine_finish", gb: 0.0, model: None, later_gb: None }]);
        assert_eq!((p.offer_nvidia, p.total_gb), (None, 0.0));

        let installed = EngineState { installed: true, partial: false, packs: Some(Packs { nvidia: true, indic: false }) };
        assert!(plan(installed, &settings(&["en"]), YES, true, TASK_READY).steps.is_empty());
        let p = plan(installed, &settings(&["en", "hi"]), YES, true, TASK_READY);
        assert_eq!(p.steps, [Step { kind: "indic", gb: 0.03, model: None, later_gb: Some(2.4) }]);
        assert_eq!(engine_packs(installed, &settings(&["en", "hi"]), YES, true).map(|p| (p.nvidia, p.indic)), Some((false, true)));
    }

    #[test]
    fn the_checkboxes_choose_the_packs() {
        let no = Choices { nvidia: false, indic: false };
        let gu = settings(&["en", "gu"]);
        assert_eq!(engine_packs(NEW, &gu, YES, true).map(|p| (p.nvidia, p.indic)), Some((true, true)));
        assert_eq!(engine_packs(NEW, &gu, no, true).map(|p| (p.nvidia, p.indic)), Some((false, false)));
        assert_eq!(engine_packs(NEW, &gu, YES, false).map(|p| p.nvidia), Some(false), "no NVIDIA pack without a big GPU");
        // Only the task model is missing (its runtime is here).
        let p = plan(NEW, &gu, no, false, (true, false, "qwen3-1.7b", 1.1));
        assert_eq!(p.steps[1], Step { kind: "task_ai", gb: 1.1, model: Some("qwen3-1.7b"), later_gb: None });
    }
}
