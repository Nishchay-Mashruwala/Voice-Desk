//! What settings and edits may be: limits, defaults, and the checks made
//! before anything is saved. The UI shows these; the backend enforces them.

use serde::Serialize;
use serde_json::{json, Value};

use crate::db::Settings;

/// A number setting's allowed range (and the step the UI moves it by).
#[derive(Debug, Clone, Copy, Serialize)]
pub struct Range {
    pub min: f64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub step: Option<f64>,
}

/// Hold the shortcut this long to start ("long" mode), in seconds.
pub const LONG_PRESS_S: Range = Range { min: 0.5, max: Some(5.0), step: Some(0.5) };
/// A pause this long ends a phrase, in ms.
pub const SILENCE_MS: Range = Range { min: 400.0, max: Some(1500.0), step: Some(50.0) };
pub const UNLOAD_AFTER_MIN: Range = Range { min: 0.0, max: None, step: Some(1.0) };
pub const KEEP_AUDIO_DAYS: Range = Range { min: 0.0, max: None, step: Some(1.0) };
/// "Play from this task" starts this many seconds before it was said.
pub const TASK_JUMP_LEAD_S: Range = Range { min: 0.0, max: Some(30.0), step: Some(1.0) };
/// Voice training: a recording shorter than this isn't enough to learn a voice;
/// it stops by itself at the maximum.
pub const VOICE_TRAINING_S: Range = Range { min: 8.0, max: Some(25.0), step: None };

/// The languages Voice Desk recognises, in the order they're stored and shown.
pub const LANGUAGES: &[&str] = &["en", "hi", "gu"];

#[derive(Debug, Serialize)]
pub struct Limits {
    pub long_press_s: Range,
    pub silence_ms: Range,
    pub unload_after_min: Range,
    pub keep_audio_days: Range,
    pub task_jump_lead_s: Range,
    pub voice_training_s: Range,
    pub languages: &'static [&'static str],
}

#[derive(Debug, Serialize)]
pub struct SettingsRules {
    pub limits: Limits,
    pub defaults: Settings,
}

pub fn settings_rules() -> SettingsRules {
    SettingsRules {
        limits: Limits {
            long_press_s: LONG_PRESS_S,
            silence_ms: SILENCE_MS,
            unload_after_min: UNLOAD_AFTER_MIN,
            keep_audio_days: KEEP_AUDIO_DAYS,
            task_jump_lead_s: TASK_JUMP_LEAD_S,
            voice_training_s: VOICE_TRAINING_S,
            languages: LANGUAGES,
        },
        defaults: Settings::default(),
    }
}

fn clamp(x: f64, r: Range) -> f64 {
    let x = x.max(r.min);
    r.max.map_or(x, |m| x.min(m))
}

/// A choice the UI can't make (only old saved settings could have one) falls
/// back to its default, so saving never fails over it.
fn known(value: &mut String, allowed: &[&str], default: String) {
    if !allowed.contains(&value.as_str()) {
        *value = default;
    }
}

/// Settings as stored and shown: the legacy single `language` becomes
/// `languages` (in the canonical order), an empty assistant name is the default.
pub fn normalized(mut s: Settings) -> Settings {
    let langs = s.langs();
    s.languages = LANGUAGES.iter().filter(|l| langs.iter().any(|x| x == *l)).map(|l| l.to_string()).collect();
    if s.languages.is_empty() {
        s.languages = vec!["en".into()];
    }
    s.assistant_name = s.assistant_name.trim().to_string();
    if s.assistant_name.is_empty() {
        s.assistant_name = Settings::default().assistant_name;
    }
    s
}

/// Check settings before they're saved: reject what can't work, clamp numbers
/// into range, and clear choices that no longer apply. Returns them as saved.
pub fn check_settings(s: Settings) -> Result<Settings, String> {
    if s.languages.is_empty() && !s.language.trim().is_empty() {
        // Old settings: one language.
    } else if !s.languages.iter().any(|l| LANGUAGES.contains(&l.as_str())) {
        return Err("Choose at least one language".into());
    }
    if let Some(l) = s.languages.iter().find(|l| !LANGUAGES.contains(&l.as_str())) {
        return Err(format!("Unknown language: {l}"));
    }
    let shortcut = check_shortcut(&s.dictation_hotkey);
    if let Some(problem) = shortcut.problem {
        return Err(problem.message().into());
    }
    let mut s = normalized(s);
    let d = Settings::default();
    known(&mut s.dictation_mode, &["toggle", "double", "long", "hold"], d.dictation_mode);
    known(&mut s.shortcut_starts, &["listen", "meeting"], d.shortcut_starts);
    known(&mut s.insert_method, &["paste", "type"], d.insert_method);
    known(&mut s.translate, &["none", "gujarati", "all"], d.translate);
    known(&mut s.prefer_indic, &["gu", "hi"], d.prefer_indic);
    let speech: Vec<&str> = crate::catalog::SPEECH_MODELS.iter().map(|m| m.id).chain(["auto"]).collect();
    known(&mut s.whisper_model, &speech, d.whisper_model);
    let task: Vec<&str> = crate::catalog::TASK_MODELS.iter().map(|m| m.id).chain(["auto"]).collect();
    known(&mut s.llm_model, &task, d.llm_model);
    let device_ok = ["auto", "cpu", "cuda"].contains(&s.device.as_str())
        || s.device.strip_prefix("cuda:").is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()));
    if !device_ok {
        s.device = d.device;
    }
    s.long_press_s = (clamp(s.long_press_s as f64, LONG_PRESS_S) * 2.0).round() as f32 / 2.0;
    s.silence_ms = clamp(s.silence_ms as f64, SILENCE_MS) as u32;
    s.task_jump_lead_s = clamp(s.task_jump_lead_s as f64, TASK_JUMP_LEAD_S) as u32;
    // "Translate Gujarati" without Gujarati is the same as writing as spoken.
    if s.translate == "gujarati" && !s.languages.iter().any(|l| l == "gu") {
        s.translate = "none".into();
    }
    Ok(s)
}

/// What's wrong with a shortcut.
#[derive(Debug, Clone, Copy, Serialize, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum ShortcutProblem {
    Empty,
    TooManyKeys,
}

impl ShortcutProblem {
    fn message(self) -> &'static str {
        match self {
            Self::Empty => "Choose a shortcut",
            Self::TooManyKeys => "The shortcut must use 1 to 3 keys",
        }
    }
}

#[derive(Debug, Serialize, PartialEq)]
pub struct ShortcutCheck {
    /// Can't be used.
    pub problem: Option<ShortcutProblem>,
    /// Works, but a key used for typing alone stops working in other apps.
    pub typing_key_alone: bool,
}

/// Keys you'd lose for normal typing if used alone as a global shortcut
/// (key codes as browsers name them: "KeyA", "Digit1", "Space"...).
fn is_typing_key(code: &str) -> bool {
    let named = [
        "Space", "Enter", "Backspace", "Tab", "Minus", "Equal", "Semicolon", "Quote", "Comma", "Period", "Slash", "Backslash",
        "Backquote",
    ];
    code.strip_prefix("Key").is_some_and(|k| k.len() == 1 && k.chars().all(|c| c.is_ascii_uppercase()))
        || code.strip_prefix("Digit").is_some_and(|d| d.len() == 1 && d.chars().all(|c| c.is_ascii_digit()))
        || code.strip_prefix("Bracket").is_some_and(|b| !b.is_empty() && b.chars().all(|c| c.is_ascii_alphanumeric()))
        || named.contains(&code)
}

/// Check a shortcut ("Ctrl+Shift+Space", "F9"): 1-3 keys, and whether it's a
/// typing key alone.
pub fn check_shortcut(shortcut: &str) -> ShortcutCheck {
    let keys: Vec<&str> = shortcut.split('+').map(str::trim).filter(|k| !k.is_empty()).collect();
    let problem = match keys.len() {
        0 => Some(ShortcutProblem::Empty),
        1..=3 => None,
        _ => Some(ShortcutProblem::TooManyKeys),
    };
    ShortcutCheck { problem, typing_key_alone: keys.len() == 1 && is_typing_key(keys[0]) }
}

/// The phrase shown for each voice command: the first of its alternatives
/// ("record task, record tasks" -> "record task").
pub fn command_phrases(s: &Settings) -> Value {
    let first = |phrases: &str| phrases.split(',').next().unwrap_or("").trim().to_string();
    json!({
        "assistant_name": normalized(s.clone()).assistant_name,
        "stop": first(&s.cmd_stop),
        "pause": first(&s.cmd_pause),
        "resume": first(&s.cmd_resume),
        "record_tasks": first(&s.cmd_record_tasks),
        "tasks_recorded": first(&s.cmd_tasks_recorded),
    })
}

/// A meeting title or task description: trimmed, and not empty.
pub fn required_text(text: &str, what: &str) -> Result<String, String> {
    let t = text.trim();
    if t.is_empty() {
        Err(format!("{what} can't be empty"))
    } else {
        Ok(t.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn settings_are_checked_and_tidied_before_saving() {
        let mut s = Settings { languages: vec!["gu".into(), "en".into()], long_press_s: 9.0, silence_ms: 10, ..Settings::default() };
        s.assistant_name = "  ".into();
        let saved = check_settings(s).unwrap();
        assert_eq!(saved.languages, ["en", "gu"], "canonical order");
        assert_eq!((saved.long_press_s, saved.silence_ms), (5.0, 400));
        assert_eq!(saved.assistant_name, "Jarvis");

        let no_langs = Settings { languages: vec![], language: String::new(), ..Settings::default() };
        assert_eq!(check_settings(no_langs).unwrap_err(), "Choose at least one language");
        // Choices the UI can't make fall back to their defaults.
        let old = Settings { whisper_model: "huge".into(), device: "cuda:x".into(), dictation_mode: "?".into(), ..Settings::default() };
        let saved = check_settings(old).unwrap();
        assert_eq!((saved.whisper_model.as_str(), saved.device.as_str(), saved.dictation_mode.as_str()), ("auto", "auto", "toggle"));
        assert_eq!(check_settings(Settings { device: "cuda:1".into(), ..Settings::default() }).unwrap().device, "cuda:1");
    }

    #[test]
    fn old_settings_with_one_language_still_save() {
        let old = Settings { languages: vec![], language: "hi".into(), ..Settings::default() };
        assert_eq!(check_settings(old).unwrap().languages, ["hi"]);
    }

    #[test]
    fn translating_gujarati_is_cleared_without_gujarati() {
        let s = Settings { languages: vec!["en".into(), "hi".into()], translate: "gujarati".into(), ..Settings::default() };
        assert_eq!(check_settings(s).unwrap().translate, "none");
        let s = Settings { languages: vec!["gu".into()], translate: "gujarati".into(), ..Settings::default() };
        assert_eq!(check_settings(s).unwrap().translate, "gujarati");
    }

    #[test]
    fn shortcuts_need_one_to_three_keys() {
        assert_eq!(check_shortcut("Ctrl+Shift+Space"), ShortcutCheck { problem: None, typing_key_alone: false });
        assert_eq!(check_shortcut("Ctrl+Alt+Shift+KeyD").problem, Some(ShortcutProblem::TooManyKeys));
        assert_eq!(check_shortcut("").problem, Some(ShortcutProblem::Empty));
        assert!(check_shortcut("KeyR").typing_key_alone);
        assert!(check_shortcut("Space").typing_key_alone && check_shortcut("BracketLeft").typing_key_alone);
        assert!(!check_shortcut("F9").typing_key_alone && !check_shortcut("Ctrl+KeyR").typing_key_alone);
    }

    #[test]
    fn shows_the_first_phrase_of_each_command() {
        let p = command_phrases(&Settings::default());
        assert_eq!((p["record_tasks"].as_str(), p["stop"].as_str()), (Some("record task"), Some("stop")));
        assert_eq!(p["assistant_name"], "Jarvis");
    }
}
