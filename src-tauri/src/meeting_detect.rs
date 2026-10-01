//! Notices when a call starts, so Voice Desk can offer to transcribe it.
//!
//! Windows keeps a list of which apps are using the microphone right now
//! (Settings → Privacy → Microphone shows it). A call is a known call app or
//! a browser (Google Meet, Zoom/Teams/WhatsApp on the web) holding the mic.
//! Videos and music never use the mic, so they never count; neither do games
//! with voice chat, which aren't on the list.

use std::collections::HashSet;
use std::time::Duration;

use tauri::{AppHandle, Emitter};

use crate::{session, Shared};

/// An app that has the microphone open for a call.
#[derive(Debug, Clone, PartialEq)]
pub struct Call {
    /// Windows' key for the app (its path or package name); stable for the call.
    pub key: String,
    /// "Zoom", "WhatsApp", "Chrome"...
    pub app: &'static str,
}

/// Executable names of call apps and browsers.
const APPS: &[(&str, &str)] = &[
    ("zoom.exe", "Zoom"),
    ("teams.exe", "Teams"),
    ("ms-teams.exe", "Teams"),
    ("whatsapp.exe", "WhatsApp"),
    ("whatsapp.root.exe", "WhatsApp"),
    ("discord.exe", "Discord"),
    ("slack.exe", "Slack"),
    ("skype.exe", "Skype"),
    ("webex.exe", "Webex"),
    ("ciscocollabhost.exe", "Webex"),
    ("atmgr.exe", "Webex"),
    ("chrome.exe", "Chrome"),
    ("msedge.exe", "Edge"),
    ("brave.exe", "Brave"),
    ("firefox.exe", "Firefox"),
    ("opera.exe", "Opera"),
    ("vivaldi.exe", "Vivaldi"),
];

/// Microsoft Store apps, by package name prefix.
const PACKAGES: &[(&str, &str)] = &[
    ("5319275a.whatsappdesktop", "WhatsApp"),
    ("msteams", "Teams"),
    ("microsoftteams", "Teams"),
    ("microsoft.skypeapp", "Skype"),
    ("zoom.zoom", "Zoom"),
];

/// Names shown in Settings.
pub const WATCHED: &str = "Zoom, Teams, WhatsApp, Discord, Slack, Skype, Webex, and browsers (Google Meet and other web calls)";

/// Which call app, if any, a microphone-list entry is. Desktop apps are
/// listed by path with `#` for `\` ("C:#Program Files#Zoom#bin#Zoom.exe").
pub fn call_app(key: &str) -> Option<&'static str> {
    let key = key.to_lowercase();
    let exe = key.rsplit('#').next().unwrap_or(&key);
    if let Some((_, name)) = APPS.iter().find(|(e, _)| *e == exe) {
        return Some(name);
    }
    PACKAGES.iter().find(|(p, _)| key.starts_with(p)).map(|(_, name)| *name)
}

/// Call apps using the microphone right now.
pub fn active_calls() -> Vec<Call> {
    native::mic_users().into_iter().filter_map(|key| call_app(&key).map(|app| Call { key, app })).collect()
}

/// Every 2 s: offer to transcribe a call that just started; take the offer
/// away when it ends. ✕ silences the offer until that app's call ends.
pub fn watch(app: AppHandle, st: Shared) {
    if !native::SUPPORTED {
        return;
    }
    std::thread::spawn(move || {
        let mut dismissed: HashSet<String> = HashSet::new();
        loop {
            std::thread::sleep(Duration::from_secs(2));
            let enabled = st.db.settings().map(|s| s.detect_meetings).unwrap_or(false);
            let calls = if enabled { active_calls() } else { Vec::new() };
            let call = calls.first().cloned();
            dismissed.retain(|k| calls.iter().any(|c| &c.key == k));
            if let Some(d) = st.call_dismiss.lock().unwrap().take() {
                dismissed.insert(d);
            }

            let changed = *st.call.lock().unwrap() != call;
            *st.call.lock().unwrap() = call.clone();
            let recording = st.meeting.lock().unwrap().is_some();
            let prompt = call.filter(|c| !recording && !dismissed.contains(&c.key));
            let prompt_changed = {
                let mut p = st.call_prompt.lock().unwrap();
                let was = p.as_ref().map(|c| c.key.clone());
                *p = prompt.clone();
                was != prompt.as_ref().map(|c| c.key.clone())
            };
            if changed || prompt_changed {
                if let Some(c) = &prompt {
                    eprintln!("[calls] {} call started", c.app);
                }
                let _ = app.emit("calls-changed", ());
                session::emit_status(&app, &st);
            }
        }
    });
}

#[cfg(windows)]
mod native {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    pub const SUPPORTED: bool = true;
    const ROOT: &str = r"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";

    /// Apps whose microphone use has started but not stopped.
    pub fn mic_users() -> Vec<String> {
        let mut out = Vec::new();
        let Ok(root) = RegKey::predef(HKEY_CURRENT_USER).open_subkey(ROOT) else { return out };
        let mut scan = |key: &RegKey| {
            for name in key.enum_keys().flatten() {
                let Ok(app) = key.open_subkey(&name) else { continue };
                if app.get_value::<u64, _>("LastUsedTimeStop").ok() == Some(0) {
                    out.push(name);
                }
            }
        };
        scan(&root);
        if let Ok(np) = root.open_subkey("NonPackaged") {
            scan(&np);
        }
        out
    }
}

/// macOS/Linux don't offer this list; detection is Windows-only for now.
#[cfg(not(windows))]
mod native {
    pub const SUPPORTED: bool = false;
    pub fn mic_users() -> Vec<String> {
        Vec::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognises_call_apps() {
        assert_eq!(call_app(r"C:#Users#me#AppData#Roaming#Zoom#bin#Zoom.exe"), Some("Zoom"));
        assert_eq!(call_app(r"C:#Program Files#Google#Chrome#Application#chrome.exe"), Some("Chrome"));
        assert_eq!(call_app(r"C:#Users#Rajvee#AppData#Local#WhatsApp#app-2.2218.8#WhatsApp.exe"), Some("WhatsApp"));
        assert_eq!(call_app("5319275A.WhatsAppDesktop_cv1g1gvanyjgm"), Some("WhatsApp"));
        assert_eq!(call_app("MSTeams_8wekyb3d8bbwe"), Some("Teams"));
    }

    #[test]
    fn ignores_games_recorders_and_itself() {
        for key in [
            r"E:#Games#Riot Games#VALORANT#live#ShooterGame#Binaries#Win64#VALORANT-Win64-Shipping.exe",
            r"C:#Users#Rajvee#OBS STUDIO#obs-studio#bin#64bit#obs64.exe",
            r"C:#Users#Rajvee#Desktop#Coding#Voice Project#src-tauri#target#debug#voicedesk.exe",
            "Microsoft.WindowsSoundRecorder_8wekyb3d8bbwe",
            // A folder named like an app doesn't count, only the program itself.
            r"C:#zoom.exe#game.exe",
        ] {
            assert_eq!(call_app(key), None, "{key}");
        }
    }
}

#[cfg(all(test, windows))]
mod live {
    /// Run while something holds the mic: `cargo test mic_users_live -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn mic_users_live() {
        // Hold the mic ourselves: this test program must show up as "in use".
        let path = std::env::temp_dir().join("vd-mic-live.wav");
        let rec = crate::audio::Recording::to_file(crate::audio::Source::Microphone, &path).unwrap();
        std::thread::sleep(std::time::Duration::from_secs(3));
        let users = super::native::mic_users();
        rec.stop().unwrap();
        let _ = std::fs::remove_file(&path);
        println!("using the mic: {users:?}");
        assert!(users.iter().any(|u| u.to_lowercase().contains("voicedesk")), "test exe not listed");
        std::thread::sleep(std::time::Duration::from_secs(2));
        let after = super::native::mic_users();
        println!("after stopping: {after:?}");
        assert!(!after.iter().any(|u| u.to_lowercase().contains("voicedesk")), "still listed after release");
    }
}
