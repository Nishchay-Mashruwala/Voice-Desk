//! Notices when a call starts, so Voice Desk can offer to transcribe it.
//!
//! Windows keeps a list of which apps are using the microphone right now
//! (Settings → Privacy → Microphone shows it). A call is a known call app or
//! a browser (Google Meet, Zoom/Teams/WhatsApp on the web) holding the mic.
//! Videos and music never use the mic, so they never count; neither do games
//! with voice chat, which aren't on the list. A browser only counts while one
//! of its windows shows a call site (Google Docs voice typing or a mic test
//! isn't a call).
//!
//! The same loop ends meetings by itself: when the call app releases the mic,
//! or when nobody has made a sound for a few minutes.

use std::collections::HashSet;
use std::time::{Duration, Instant};

use serde_json::json;
use tauri::{AppHandle, Emitter};

use crate::audio::{Recording, Sink, Source};
use crate::{meetings, session, Shared};

/// After the call app releases the mic, wait this long before ending the meeting.
pub const CALL_END_GRACE: Duration = Duration::from_secs(15);
/// No sound on the mic or the speakers for this long ends a meeting, and
/// withdraws a call offer (some apps, Teams especially, keep the mic open).
pub const QUIET_LIMIT: Duration = Duration::from_secs(180);
/// Listening when a call starts: after this long the listening becomes a
/// meeting recording (✕ on the offer cancels it).
pub const SWITCH_TO_MEETING: Duration = Duration::from_secs(10);
/// RMS level (0-1) that counts as someone making a sound: speech is ~0.02-0.1,
/// room noise on a laptop mic ~0.002-0.005, a silent call 0.
pub const SOUND_LEVEL: f32 = 0.01;

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

/// Browsers: only a call while a window title names a call site.
const BROWSERS: &[&str] = &["Chrome", "Edge", "Brave", "Firefox", "Opera", "Vivaldi"];

/// Call sites, as they appear in a browser window's title (the active tab's title).
const CALL_SITES: &[&str] = &[
    "google meet", "meet -", "meet –", "zoom", "microsoft teams", "| teams", "whatsapp", "discord", "slack",
    "webex", "skype", "messenger", "jitsi", "whereby", "gather", "around",
];

/// Does this browser window title belong to a call site?
pub fn is_call_title(title: &str) -> bool {
    let t = title.to_lowercase();
    CALL_SITES.iter().any(|site| t.contains(site))
}

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

/// Call apps using the microphone right now (browsers: any, before the title check).
pub fn active_calls() -> Vec<Call> {
    native::mic_users().into_iter().filter_map(|key| call_app(&key).map(|app| Call { key, app })).collect()
}

/// What the meeting watcher decides on each check.
#[derive(Debug, PartialEq)]
pub enum MeetingCheck {
    KeepGoing,
    CallEnded,
    Quiet,
}

/// Should a meeting end now? `call_gone_for`: how long its call app has had
/// the mic released (None: still on, or not started from a call);
/// `quiet_for`: time since anyone made a sound.
pub fn check_meeting(call_gone_for: Option<Duration>, quiet_for: Duration) -> MeetingCheck {
    if call_gone_for.is_some_and(|d| d >= CALL_END_GRACE) {
        MeetingCheck::CallEnded
    } else if quiet_for >= QUIET_LIMIT {
        MeetingCheck::Quiet
    } else {
        MeetingCheck::KeepGoing
    }
}

/// When listening becomes a meeting recording: the offered call's key and the
/// moment. Kept while the same call is offered and you keep listening; reset
/// when either changes (✕ removes the offer, so it cancels too).
pub fn switch_deadline(prev: Option<(String, Instant)>, offered: Option<&str>, listening: bool, now: Instant) -> Option<(String, Instant)> {
    let key = offered.filter(|_| listening)?;
    match prev {
        Some((k, at)) if k == key => Some((k, at)),
        _ => Some((key.to_string(), now + SWITCH_TO_MEETING)),
    }
}

/// State the watcher keeps between checks.
#[derive(Default)]
struct Watch {
    /// ✕ on the offer, until that app releases the mic.
    dismissed: HashSet<String>,
    /// Browsers confirmed as calls (stays until the mic is released).
    browser_calls: HashSet<String>,
    /// The current meeting's call app: when it released the mic.
    call_gone_since: Option<Instant>,
    /// Last time anyone made a sound in the meeting / while an offer is shown.
    last_sound: Option<Instant>,
    /// Listens to the speakers (levels only) while an offer is shown.
    offer_probe: Option<(String, Recording, Instant)>,
    /// Listening during the offered call: when it becomes a meeting recording.
    switch: Option<(String, Instant)>,
}

/// Every 2 s: offer to transcribe a call that just started; take the offer
/// away when it ends or goes quiet; end meetings whose call ended.
pub fn watch(app: AppHandle, st: Shared) {
    if !native::SUPPORTED {
        return;
    }
    std::thread::spawn(move || {
        let mut w = Watch::default();
        loop {
            std::thread::sleep(Duration::from_secs(2));
            tick(&app, &st, &mut w);
        }
    });
}

fn tick(app: &AppHandle, st: &Shared, w: &mut Watch) {
    let settings = st.db.settings().unwrap_or_default();
    let mic_users = if settings.detect_meetings || settings.auto_stop_meetings { active_calls() } else { Vec::new() };
    let held: HashSet<String> = mic_users.iter().map(|c| c.key.clone()).collect();
    w.dismissed.retain(|k| held.contains(k));
    w.browser_calls.retain(|k| held.contains(k));
    if let Some(d) = st.call_dismiss.lock().unwrap().take() {
        w.dismissed.insert(d);
    }

    // Browsers count only while showing a call site (checked until confirmed).
    let calls: Vec<Call> = mic_users
        .into_iter()
        .filter(|c| {
            if !BROWSERS.contains(&c.app) || w.browser_calls.contains(&c.key) {
                return true;
            }
            let exe = c.key.rsplit('#').next().unwrap_or(&c.key).to_lowercase();
            let is_call = native::window_titles(&exe).iter().any(|t| is_call_title(t));
            if is_call {
                w.browser_calls.insert(c.key.clone());
            }
            is_call
        })
        .collect();
    let call = if settings.detect_meetings { calls.first().cloned() } else { None };

    watch_meeting(app, st, w, &held, settings.auto_stop_meetings);

    // The offer.
    let recording = st.meeting.lock().unwrap().is_some();
    let mut offer = call.clone().filter(|c| !recording && !w.dismissed.contains(&c.key));
    if let Some(c) = &offer {
        if offer_went_quiet(w, c) {
            eprintln!("[calls] {} quiet for {}s: offer withdrawn", c.app, QUIET_LIMIT.as_secs());
            w.dismissed.insert(c.key.clone());
            offer = None;
        }
    }
    if offer.is_none() {
        w.offer_probe = None;
    }

    let changed = *st.call.lock().unwrap() != call;
    *st.call.lock().unwrap() = call;
    let offer_changed = {
        let mut p = st.call_prompt.lock().unwrap();
        let was = p.as_ref().map(|c| c.key.clone());
        *p = offer.clone();
        was != offer.as_ref().map(|c| c.key.clone())
    };
    // Listening when the call started: it becomes a meeting recording.
    let now = Instant::now();
    let switch = switch_deadline(w.switch.take(), offer.as_ref().map(|c| c.key.as_str()), session::is_listening(st), now);
    let switch_changed = *st.call_switch_at.lock().unwrap() != switch.as_ref().map(|s| s.1);
    *st.call_switch_at.lock().unwrap() = switch.as_ref().map(|s| s.1);
    if switch.as_ref().is_some_and(|s| now >= s.1) {
        *st.call_switch_at.lock().unwrap() = None;
        if let Some(c) = &offer {
            eprintln!("[calls] listening during the {} call: switching to a meeting recording", c.app);
        }
        if let Err(e) = meetings::accept_call(app, st) {
            eprintln!("[calls] couldn't switch to a meeting recording: {e}");
        }
        return;
    }
    w.switch = switch;

    if changed || offer_changed || switch_changed {
        if let Some(c) = offer.as_ref().filter(|_| offer_changed) {
            eprintln!("[calls] {} call started", c.app);
        }
        let _ = app.emit("calls-changed", ());
        session::emit_status(app, st);
    }
}

/// End the meeting when its call ended or everyone has been quiet too long.
fn watch_meeting(app: &AppHandle, st: &Shared, w: &mut Watch, held: &HashSet<String>, auto_stop: bool) {
    let (call_key, loud) = match st.meeting.lock().unwrap().as_ref() {
        Some(m) => {
            let level = m.mic.level().max(m.system.as_ref().map_or(0.0, |s| s.level()));
            (Some(m.call_key.clone()), level >= SOUND_LEVEL)
        }
        None => (None, false),
    };
    let Some(call_key) = call_key else {
        w.call_gone_since = None;
        w.last_sound = None;
        return;
    };
    let now = Instant::now();
    if loud || w.last_sound.is_none() {
        w.last_sound = Some(now);
    }
    match &call_key {
        Some(k) if !held.contains(k) => {
            w.call_gone_since.get_or_insert(now);
        }
        _ => w.call_gone_since = None,
    }
    if !auto_stop {
        return;
    }
    let verdict = check_meeting(w.call_gone_since.map(|t| now - t), now - w.last_sound.unwrap_or(now));
    let message = match verdict {
        MeetingCheck::KeepGoing => return,
        MeetingCheck::CallEnded => "The call ended, so the meeting recording stopped. Finding tasks…",
        MeetingCheck::Quiet => "Nobody has spoken for 3 minutes, so the meeting recording stopped. Finding tasks…",
    };
    w.call_gone_since = None;
    w.last_sound = None;
    let (app, st) = (app.clone(), st.clone());
    tauri::async_runtime::spawn(async move {
        if meetings::end_meeting(&app, &st).await.is_ok() {
            let _ = app.emit("session-notice", json!({ "message": message, "short": "✓ Meeting saved" }));
        }
    });
}

/// While the offer is shown, listen to the speakers (levels only, nothing is
/// saved). True once nothing has been heard for QUIET_LIMIT.
fn offer_went_quiet(w: &mut Watch, call: &Call) -> bool {
    let now = Instant::now();
    if w.offer_probe.as_ref().map(|p| &p.0) != Some(&call.key) {
        let probe = Recording::start(Source::System, Sink::Live(Box::new(|_| {}), None)).ok();
        w.offer_probe = probe.map(|r| (call.key.clone(), r, now));
        return false;
    }
    let Some((_, probe, last)) = w.offer_probe.as_mut() else { return false };
    if probe.level() >= SOUND_LEVEL {
        *last = now;
    }
    now - *last >= QUIET_LIMIT
}

#[cfg(windows)]
mod native {
    use winreg::enums::HKEY_CURRENT_USER;
    use winreg::RegKey;

    pub const SUPPORTED: bool = true;

    /// Titles of the visible top-level windows of processes named `exe` ("chrome.exe").
    pub fn window_titles(exe: &str) -> Vec<String> {
        use sysinfo::{ProcessesToUpdate, System};
        use windows::core::BOOL;
        use windows::Win32::Foundation::{HWND, LPARAM};
        use windows::Win32::UI::WindowsAndMessaging::{EnumWindows, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible};

        let mut sys = System::new();
        sys.refresh_processes(ProcessesToUpdate::All, false);
        let pids: std::collections::HashSet<u32> = sys
            .processes()
            .iter()
            .filter(|(_, p)| p.name().to_string_lossy().eq_ignore_ascii_case(exe))
            .map(|(pid, _)| pid.as_u32())
            .collect();
        if pids.is_empty() {
            return Vec::new();
        }
        struct Ctx {
            pids: std::collections::HashSet<u32>,
            titles: Vec<String>,
        }
        unsafe extern "system" fn each(hwnd: HWND, lparam: LPARAM) -> BOOL {
            let ctx = &mut *(lparam.0 as *mut Ctx);
            let mut pid = 0u32;
            GetWindowThreadProcessId(hwnd, Some(&mut pid));
            if ctx.pids.contains(&pid) && IsWindowVisible(hwnd).as_bool() {
                let mut buf = [0u16; 512];
                let n = GetWindowTextW(hwnd, &mut buf);
                if n > 0 {
                    ctx.titles.push(String::from_utf16_lossy(&buf[..n as usize]));
                }
            }
            BOOL(1)
        }
        let mut ctx = Ctx { pids, titles: Vec::new() };
        unsafe {
            let _ = EnumWindows(Some(each), LPARAM(&mut ctx as *mut Ctx as isize));
        }
        ctx.titles
    }

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
    pub fn window_titles(_exe: &str) -> Vec<String> {
        Vec::new()
    }
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
    fn browser_titles_of_calls() {
        for t in [
            "Meet - abc-defg-hij - Google Chrome",
            "Meet – Weekly sync - Microsoft\u{200b} Edge",
            "(2) WhatsApp - Google Chrome",
            "Zoom Meeting - Brave",
            "Chat | Microsoft Teams - Google Chrome",
        ] {
            assert!(is_call_title(t), "{t}");
        }
        for t in ["Untitled document - Google Docs - Google Chrome", "Online Mic Test - Google Chrome", "YouTube - Brave"] {
            assert!(!is_call_title(t), "{t}");
        }
    }

    #[test]
    fn meetings_end_when_the_call_ends_or_goes_quiet() {
        let s = Duration::from_secs;
        assert_eq!(check_meeting(None, s(10)), MeetingCheck::KeepGoing);
        assert_eq!(check_meeting(Some(s(5)), s(10)), MeetingCheck::KeepGoing); // brief mic release
        assert_eq!(check_meeting(Some(s(15)), s(10)), MeetingCheck::CallEnded);
        assert_eq!(check_meeting(None, s(179)), MeetingCheck::KeepGoing);
        assert_eq!(check_meeting(None, s(180)), MeetingCheck::Quiet);
    }

    #[test]
    fn listening_becomes_a_meeting_after_ten_seconds_of_the_same_call() {
        let t0 = Instant::now();
        let first = switch_deadline(None, Some("zoom"), true, t0).unwrap();
        assert_eq!(first, ("zoom".to_string(), t0 + SWITCH_TO_MEETING));
        // Same call, still listening: the deadline doesn't move.
        let later = switch_deadline(Some(first.clone()), Some("zoom"), true, t0 + Duration::from_secs(6));
        assert_eq!(later, Some(first.clone()));
        // Another call starts the 10 s again.
        let other = switch_deadline(Some(first.clone()), Some("teams"), true, t0 + Duration::from_secs(6)).unwrap();
        assert_eq!(other.1, t0 + Duration::from_secs(6) + SWITCH_TO_MEETING);
        // Not listening, or the offer dismissed (✕) / gone: no switch.
        assert_eq!(switch_deadline(Some(first.clone()), Some("zoom"), false, t0), None);
        assert_eq!(switch_deadline(Some(first), None, true, t0), None);
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
    /// `cargo test window_titles_live -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn window_titles_live() {
        for exe in ["code.exe", "chrome.exe", "msedge.exe", "explorer.exe"] {
            let titles = super::native::window_titles(exe);
            println!("{exe}: {} windows {:?}", titles.len(), titles.iter().take(3).collect::<Vec<_>>());
        }
        assert!(!super::native::window_titles("code.exe").is_empty(), "VS Code is open, so it has a window");
    }

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
