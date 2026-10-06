//! Notices when a call starts, so Voice Desk can offer to transcribe it.
//!
//! Each system can say which apps are recording from the microphone right now:
//! Windows keeps a list (Settings → Privacy → Microphone shows it), macOS
//! 14.2+ lists CoreAudio processes that are running input, and on Linux
//! PipeWire/PulseAudio lists recording streams (`pactl`). A call is a known call app or
//! a browser (Google Meet, Zoom/Teams/WhatsApp on the web) holding the mic.
//! Videos and music never use the mic, so they never count; neither do games
//! with voice chat, which aren't on the list. A browser only counts while one
//! of its windows shows a call site (Google Docs voice typing or a mic test
//! isn't a call). Where its window titles can't be read (macOS without the
//! Screen Recording permission, Wayland on Linux), a browser counts while it
//! is also playing sound: a call both records and plays, dictation only records.
//!
//! The same loop ends meetings by itself: when the call app releases the mic,
//! or when nobody has made a sound for a few minutes.

use std::collections::{HashMap, HashSet};
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
    /// The system's key for the app; stable for the call. Windows: its path
    /// (`#` for `\`) or package name. macOS: its bundle id (or executable path).
    /// Linux: its executable's name ("zoom", "chrome").
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

/// Linux executable names (and macOS executables without a bundle id).
const BINARIES: &[(&str, &str)] = &[
    ("zoom", "Zoom"),
    ("zoom.us", "Zoom"),
    ("teams", "Teams"),
    ("teams-for-linux", "Teams"),
    ("whatsapp-for-linux", "WhatsApp"),
    ("whatsie", "WhatsApp"),
    ("discord", "Discord"),
    ("discordptb", "Discord"),
    ("discordcanary", "Discord"),
    ("slack", "Slack"),
    ("skypeforlinux", "Skype"),
    ("webex", "Webex"),
    ("ciscocollabhost", "Webex"),
    ("chrome", "Chrome"),
    ("google-chrome", "Chrome"),
    ("google-chrome-stable", "Chrome"),
    ("chromium", "Chromium"),
    ("chromium-browser", "Chromium"),
    ("msedge", "Edge"),
    ("microsoft-edge", "Edge"),
    ("brave", "Brave"),
    ("brave-browser", "Brave"),
    ("firefox", "Firefox"),
    ("firefox-bin", "Firefox"),
    ("firefox-esr", "Firefox"),
    ("opera", "Opera"),
    ("vivaldi", "Vivaldi"),
    ("vivaldi-bin", "Vivaldi"),
];

/// macOS bundle ids (lowercase). An id also covers its helpers: CoreAudio often
/// names the helper that records ("com.google.Chrome.helper"), not the app.
const BUNDLES: &[(&str, &str)] = &[
    ("us.zoom.xos", "Zoom"),
    ("com.microsoft.teams2", "Teams"),
    ("com.microsoft.teams", "Teams"),
    ("net.whatsapp.whatsapp", "WhatsApp"),
    ("desktop.whatsapp", "WhatsApp"),
    ("com.hnc.discord", "Discord"),
    ("com.tinyspeck.slackmacgap", "Slack"),
    ("cisco-systems.spark", "Webex"),
    ("com.skype.skype", "Skype"),
    ("com.apple.facetime", "FaceTime"),
    // FaceTime's calls run in this daemon.
    ("com.apple.avconferenced", "FaceTime"),
    ("com.google.chrome", "Chrome"),
    ("org.chromium.chromium", "Chromium"),
    ("com.microsoft.edgemac", "Edge"),
    ("com.brave.browser", "Brave"),
    ("org.mozilla.firefox", "Firefox"),
    // Firefox's child processes.
    ("org.mozilla.plugincontainer", "Firefox"),
    ("com.operasoftware.opera", "Opera"),
    ("com.vivaldi.vivaldi", "Vivaldi"),
    ("com.apple.safari", "Safari"),
    // Safari records in WebKit's processes (shared with other apps' web views;
    // the window title check only looks at Safari's windows).
    ("com.apple.webkit.gpu", "Safari"),
    ("com.apple.webkit.webcontent", "Safari"),
];

/// macOS window owners (app names, lowercase prefixes) of browsers.
const MAC_WINDOW_OWNERS: &[(&str, &str)] = &[
    ("google chrome", "Chrome"),
    ("chromium", "Chromium"),
    ("microsoft edge", "Edge"),
    ("brave browser", "Brave"),
    ("firefox", "Firefox"),
    ("opera", "Opera"),
    ("vivaldi", "Vivaldi"),
    ("safari", "Safari"),
];

/// Browsers: only a call while a window title names a call site.
const BROWSERS: &[&str] = &["Chrome", "Chromium", "Edge", "Brave", "Firefox", "Opera", "Vivaldi", "Safari"];

/// Voice Desk's own bundle id (tauri.conf.json); never a call.
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
const OWN_BUNDLE_ID: &str = "com.rajvee.voicedesk";

/// Call sites, as they appear in a browser window's title (the active tab's title).
const CALL_SITES: &[&str] = &[
    "google meet", "meet -", "meet –", "zoom", "microsoft teams", "| teams", "whatsapp", "discord", "slack",
    "webex", "skype", "messenger", "jitsi", "whereby", "gather",
];

/// Video and music sites: never a call, even when the title names a call app
/// ("Zoom tutorial for beginners - YouTube").
const MEDIA_SITES: &[&str] = &[
    "youtube", "netflix", "twitch", "spotify", "prime video", "vimeo", "hotstar", "disney+", "jiocinema", "soundcloud",
];

/// Does this browser window title belong to a call site?
pub fn is_call_title(title: &str) -> bool {
    let t = title.to_lowercase();
    // Google Meet's own title leads with "Meet - <meeting name>", whatever the name says.
    if t.starts_with("meet - ") || t.starts_with("meet – ") {
        return true;
    }
    CALL_SITES.iter().any(|site| t.contains(site)) && !MEDIA_SITES.iter().any(|site| t.contains(site))
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
#[cfg(windows)]
pub const WATCHED: &str = "Zoom, Teams, WhatsApp, Discord, Slack, Skype, Webex, and browsers (Google Meet and other web calls)";
#[cfg(target_os = "macos")]
pub const WATCHED: &str = "Zoom, Teams, WhatsApp, Discord, Slack, Skype, Webex, FaceTime, and browsers (Google Meet and other web calls)";
#[cfg(not(any(windows, target_os = "macos")))]
pub const WATCHED: &str = "Zoom, Teams, WhatsApp, Discord, Slack, Skype, Webex, and browsers (Google Meet and other web calls). Needs pactl (PipeWire or PulseAudio)";

/// Which call app, if any, a microphone-list entry is. Windows lists desktop
/// apps by path with `#` for `\` ("C:#Program Files#Zoom#bin#Zoom.exe") and
/// Store apps by package; macOS by bundle id ("us.zoom.xos") or path; Linux by
/// executable name ("zoom").
pub fn call_app(key: &str) -> Option<&'static str> {
    let key = key.to_lowercase();
    let exe = key.rsplit(['#', '/']).next().unwrap_or(&key);
    if let Some((_, name)) = APPS.iter().chain(BINARIES).find(|(e, _)| *e == exe) {
        return Some(name);
    }
    if let Some((_, name)) =
        BUNDLES.iter().find(|(id, _)| key == *id || key.strip_prefix(id).is_some_and(|rest| rest.starts_with('.')))
    {
        return Some(name);
    }
    PACKAGES.iter().find(|(p, _)| key.starts_with(p)).map(|(_, name)| *name)
}

/// Which browser owns a macOS window, by its owner's name ("Google Chrome").
#[cfg_attr(not(target_os = "macos"), allow(dead_code))]
fn mac_window_app(owner: &str) -> Option<&'static str> {
    let owner = owner.to_lowercase();
    MAC_WINDOW_OWNERS.iter().find(|(o, _)| owner.starts_with(o)).map(|(_, app)| *app)
}

/// Is a window of app `window_app` one of `call_app`'s? (Chrome and Chromium
/// share their executable's name on some Linux packages.)
#[cfg_attr(windows, allow(dead_code))]
fn same_browser(window_app: Option<&str>, call_app: &str) -> bool {
    let chromes = ["Chrome", "Chromium"];
    window_app == Some(call_app) || window_app.is_some_and(|w| chromes.contains(&w) && chromes.contains(&call_app))
}

/// Without readable titles, a browser must record and play for this long to
/// count as a call: voice search or a quick mic test doesn't.
pub const BROWSER_SUSTAIN: Duration = Duration::from_secs(20);

/// Is a browser holding the mic in a call? `titles`: its windows' titles, None
/// when they can't be read; then a call is a browser that has also been
/// playing sound for BROWSER_SUSTAIN (`playing_since` keeps that between checks).
pub fn browser_is_call(
    titles: Option<&[String]>,
    playing: impl FnOnce() -> bool,
    playing_since: &mut Option<Instant>,
    now: Instant,
) -> bool {
    match titles {
        Some(titles) => {
            *playing_since = None;
            titles.iter().any(|t| is_call_title(t))
        }
        None if playing() => now - *playing_since.get_or_insert(now) >= BROWSER_SUSTAIN,
        None => {
            *playing_since = None;
            false
        }
    }
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
    /// Browsers without readable titles: since when they've recorded and played.
    browser_playing: HashMap<String, Option<Instant>>,
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
    w.browser_playing.retain(|k, _| held.contains(k));
    if let Some(d) = st.call_dismiss.lock().unwrap().take() {
        w.dismissed.insert(d);
    }

    // Browsers count only while showing a call site, or while playing sound
    // where titles can't be read (checked until confirmed).
    let calls: Vec<Call> = mic_users
        .into_iter()
        .filter(|c| {
            if !BROWSERS.contains(&c.app) || w.browser_calls.contains(&c.key) {
                return true;
            }
            let since = w.browser_playing.entry(c.key.clone()).or_default();
            let is_call = browser_is_call(native::window_titles(c).as_deref(), || native::playing(c), since, Instant::now());
            if is_call {
                w.browser_calls.insert(c.key.clone());
            }
            is_call
        })
        .collect();
    let call = if settings.detect_meetings { calls.first().cloned() } else { None };

    watch_meeting(app, st, w, &held, &calls, settings.auto_stop_meetings);

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

/// The call a meeting recording belongs to. One started before its call (from
/// the shortcut before joining, or with call offers off) takes the first call
/// seen while it records, so it still ends when that call does.
pub fn meeting_call(current: Option<String>, calls: &[Call]) -> Option<String> {
    current.or_else(|| calls.first().map(|c| c.key.clone()))
}

/// End the meeting when its call ended or everyone has been quiet too long.
fn watch_meeting(app: &AppHandle, st: &Shared, w: &mut Watch, held: &HashSet<String>, calls: &[Call], auto_stop: bool) {
    let (call_key, loud) = match st.meeting.lock().unwrap().as_mut() {
        Some(m) => {
            if m.call_key.is_none() {
                m.call_key = meeting_call(None, calls);
                if let Some(c) = calls.first() {
                    eprintln!("[calls] the meeting recording belongs to the {} call: it ends with it", c.app);
                }
            }
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
/// Not on macOS: listening to the speakers there asks for the "System Audio
/// Recording" permission and shows the recording indicator, which an offer
/// shouldn't do; the offer goes when the call app releases the mic.
fn offer_went_quiet(w: &mut Watch, call: &Call) -> bool {
    if cfg!(target_os = "macos") {
        return false;
    }
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

    /// Titles of the visible windows of the app holding the mic (always readable).
    pub fn window_titles(call: &super::Call) -> Option<Vec<String>> {
        let exe = call.key.rsplit('#').next().unwrap_or(&call.key).to_lowercase();
        Some(exe_window_titles(&exe))
    }

    /// Not needed: titles are always readable on Windows.
    pub fn playing(_call: &super::Call) -> bool {
        false
    }

    /// Titles of the visible top-level windows of processes named `exe` ("chrome.exe").
    pub fn exe_window_titles(exe: &str) -> Vec<String> {
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

/// Reading what Linux tools print (pure, so it's tested on every system).
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
mod linux_parse {
    /// A stream recording from a source (`pactl list source-outputs`) or playing
    /// to a sink (`pactl list sink-inputs`).
    #[derive(Debug, Default, PartialEq)]
    pub struct Stream {
        /// application.process.binary ("zoom")
        pub binary: String,
        /// application.name ("ZOOM VoiceEngine")
        pub name: String,
        /// application.process.id
        pub pid: Option<u32>,
        /// Paused (a stopped video can keep its stream for a while).
        pub corked: bool,
    }

    /// `pactl --format=json list source-outputs` (or `sink-inputs`). None if it isn't JSON (older
    /// pactl, or one that prints broken JSON): read the text output instead.
    pub fn pactl_json(s: &str) -> Option<Vec<Stream>> {
        let v: serde_json::Value = serde_json::from_str(s).ok()?;
        let prop = |o: &serde_json::Value, k: &str| match &o["properties"][k] {
            serde_json::Value::String(s) => s.clone(),
            serde_json::Value::Number(n) => n.to_string(),
            _ => String::new(),
        };
        Some(
            v.as_array()?
                .iter()
                .map(|o| Stream {
                    binary: prop(o, "application.process.binary"),
                    name: prop(o, "application.name"),
                    pid: prop(o, "application.process.id").parse().ok(),
                    corked: o["corked"].as_bool().unwrap_or(false),
                })
                .collect(),
        )
    }

    /// `LC_ALL=C pactl list source-outputs` (or `sink-inputs`).
    pub fn pactl_text(s: &str) -> Vec<Stream> {
        let mut out: Vec<Stream> = Vec::new();
        for line in s.lines() {
            let line = line.trim();
            if line.starts_with("Source Output #") || line.starts_with("Sink Input #") {
                out.push(Stream::default());
                continue;
            }
            if let (Some(cur), Some(v)) = (out.last_mut(), line.strip_prefix("Corked:")) {
                cur.corked = v.trim() == "yes";
                continue;
            }
            let (Some(cur), Some((k, v))) = (out.last_mut(), line.split_once(" = ")) else { continue };
            match k {
                "application.process.binary" => cur.binary = unquote(v),
                "application.name" => cur.name = unquote(v),
                "application.process.id" => cur.pid = unquote(v).parse().ok(),
                _ => {}
            }
        }
        out
    }

    /// Keys of the apps recording (their executable, else their name), without
    /// Voice Desk itself (`own_pid`) and without repeats.
    pub fn stream_keys(streams: &[Stream], own_pid: u32) -> Vec<String> {
        let is_us = |n: &str| ["voicedesk", "voice desk"].contains(&n.to_lowercase().as_str());
        let mut keys: Vec<String> = Vec::new();
        for s in streams {
            let key = if s.binary.is_empty() { &s.name } else { &s.binary };
            if s.pid == Some(own_pid) || key.is_empty() || is_us(key) || is_us(&s.name) || keys.contains(key) {
                continue;
            }
            keys.push(key.clone());
        }
        keys
    }

    /// A quoted value from pactl or xprop: `"Meet \"x\""`, octal `\342\200\223`.
    pub fn unquote(v: &str) -> String {
        let v = v.trim();
        let inner = v.strip_prefix('"').and_then(|x| x.strip_suffix('"')).unwrap_or(v).as_bytes();
        let mut out = Vec::with_capacity(inner.len());
        let mut i = 0;
        while i < inner.len() {
            if inner[i] == b'\\' && i + 1 < inner.len() {
                let oct = &inner[i + 1..(i + 4).min(inner.len())];
                if oct.len() == 3 && oct.iter().all(|c| (b'0'..=b'7').contains(c)) {
                    let n = oct.iter().fold(0u32, |n, c| n * 8 + u32::from(c - b'0'));
                    if let Ok(b) = u8::try_from(n) {
                        out.push(b);
                        i += 4;
                        continue;
                    }
                }
                out.push(inner[i + 1]);
                i += 2;
                continue;
            }
            out.push(inner[i]);
            i += 1;
        }
        String::from_utf8_lossy(&out).into_owned()
    }

    /// `wmctrl -lp`: "0x03a00003  0 4242   host Window title" → (pid, title).
    pub fn wmctrl(s: &str) -> Vec<(u32, String)> {
        s.lines()
            .filter_map(|line| {
                let mut rest = line;
                let mut fields = [""; 4];
                for f in fields.iter_mut() {
                    rest = rest.trim_start();
                    let end = rest.find(char::is_whitespace).unwrap_or(rest.len());
                    *f = &rest[..end];
                    rest = &rest[end..];
                }
                let pid = fields[2].parse::<u32>().ok().filter(|&p| p > 0)?;
                let title = rest.trim();
                (!title.is_empty()).then(|| (pid, title.to_string()))
            })
            .collect()
    }

    /// `xprop -root _NET_CLIENT_LIST` → window ids ("0x1e00003").
    pub fn client_list(s: &str) -> Vec<String> {
        let Some((_, ids)) = s.split_once('#') else { return Vec::new() };
        ids.split(',').map(str::trim).filter(|id| id.starts_with("0x")).map(String::from).collect()
    }

    /// `xprop -id <w> _NET_WM_PID _NET_WM_NAME WM_NAME` → (pid, title).
    pub fn xprop_window(s: &str) -> Option<(u32, String)> {
        let (mut pid, mut net_name, mut name) = (None, None, None);
        for line in s.lines() {
            let Some((k, v)) = line.split_once(" = ") else { continue };
            match k.split('(').next().unwrap_or(k).trim() {
                "_NET_WM_PID" => pid = v.trim().parse::<u32>().ok(),
                "_NET_WM_NAME" => net_name = Some(unquote(v)),
                "WM_NAME" => name = Some(unquote(v)),
                _ => {}
            }
        }
        let title = net_name.or(name).filter(|t| !t.is_empty())?;
        Some((pid.filter(|&p| p > 0)?, title))
    }
}

/// macOS 14.2+: CoreAudio lists the processes using audio and whether each is
/// recording or playing; window titles come from the window server
/// (CGWindowList), which only shares them with apps that have the Screen
/// Recording permission. Without it (Voice Desk never asks), a browser counts
/// as a call while it records and plays at once.
#[cfg(target_os = "macos")]
mod native {
    use std::ffi::{c_char, c_void, CStr};
    use std::ptr;

    pub const SUPPORTED: bool = true;

    type OSStatus = i32;
    type AudioObjectID = u32;
    type CFTypeRef = *const c_void;
    type CFStringRef = *const c_void;
    type CFArrayRef = *const c_void;
    type CFDictionaryRef = *const c_void;
    type CFIndex = isize;
    type CFTypeID = usize;

    #[repr(C)]
    struct AudioObjectPropertyAddress {
        selector: u32,
        scope: u32,
        element: u32,
    }

    const fn fourcc(c: &[u8; 4]) -> u32 {
        u32::from_be_bytes(*c)
    }
    // From CoreAudio/AudioHardware.h (process objects: macOS 14.2+); the same
    // values as objc2-core-audio 0.3.2's generated AudioHardware.rs.
    const SYSTEM_OBJECT: AudioObjectID = 1; // kAudioObjectSystemObject
    const SCOPE_GLOBAL: u32 = fourcc(b"glob"); // kAudioObjectPropertyScopeGlobal
    const ELEMENT_MAIN: u32 = 0; // kAudioObjectPropertyElementMain
    const PROCESS_OBJECT_LIST: u32 = fourcc(b"prs#"); // kAudioHardwarePropertyProcessObjectList
    const PROCESS_PID: u32 = fourcc(b"ppid"); // kAudioProcessPropertyPID
    const PROCESS_BUNDLE_ID: u32 = fourcc(b"pbid"); // kAudioProcessPropertyBundleID
    const PROCESS_IS_RUNNING_INPUT: u32 = fourcc(b"piri"); // kAudioProcessPropertyIsRunningInput
    const PROCESS_IS_RUNNING_OUTPUT: u32 = fourcc(b"piro"); // kAudioProcessPropertyIsRunningOutput

    const UTF8: u32 = 0x0800_0100; // kCFStringEncodingUTF8
    const ON_SCREEN_ONLY: u32 = 1 << 0; // kCGWindowListOptionOnScreenOnly
    const EXCLUDE_DESKTOP: u32 = 1 << 4; // kCGWindowListExcludeDesktopElements
    const PROC_PIDPATHINFO_MAXSIZE: usize = 4096;

    #[link(name = "CoreAudio", kind = "framework")]
    extern "C" {
        fn AudioObjectGetPropertyDataSize(
            object: AudioObjectID,
            address: *const AudioObjectPropertyAddress,
            qualifier_size: u32,
            qualifier: *const c_void,
            out_size: *mut u32,
        ) -> OSStatus;
        fn AudioObjectGetPropertyData(
            object: AudioObjectID,
            address: *const AudioObjectPropertyAddress,
            qualifier_size: u32,
            qualifier: *const c_void,
            io_size: *mut u32,
            out_data: *mut c_void,
        ) -> OSStatus;
    }

    #[link(name = "CoreFoundation", kind = "framework")]
    extern "C" {
        fn CFRelease(cf: CFTypeRef);
        fn CFGetTypeID(cf: CFTypeRef) -> CFTypeID;
        fn CFStringGetTypeID() -> CFTypeID;
        fn CFStringGetLength(s: CFStringRef) -> CFIndex;
        fn CFStringGetMaximumSizeForEncoding(length: CFIndex, encoding: u32) -> CFIndex;
        fn CFStringGetCString(s: CFStringRef, buffer: *mut c_char, size: CFIndex, encoding: u32) -> u8;
        fn CFArrayGetCount(array: CFArrayRef) -> CFIndex;
        fn CFArrayGetValueAtIndex(array: CFArrayRef, index: CFIndex) -> *const c_void;
        fn CFDictionaryGetValue(dict: CFDictionaryRef, key: *const c_void) -> *const c_void;
    }

    #[link(name = "CoreGraphics", kind = "framework")]
    extern "C" {
        fn CGWindowListCopyWindowInfo(option: u32, relative_to_window: u32) -> CFArrayRef;
        static kCGWindowOwnerName: CFStringRef;
        static kCGWindowName: CFStringRef;
    }

    extern "C" {
        // libproc.h (libSystem)
        fn proc_pidpath(pid: i32, buffer: *mut c_void, size: u32) -> i32;
    }

    fn address(selector: u32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress { selector, scope: SCOPE_GLOBAL, element: ELEMENT_MAIN }
    }

    /// A CFString's text (the caller still owns `s`).
    unsafe fn cf_string(s: CFStringRef) -> Option<String> {
        if s.is_null() || CFGetTypeID(s) != CFStringGetTypeID() {
            return None;
        }
        let size = CFStringGetMaximumSizeForEncoding(CFStringGetLength(s), UTF8).max(0) + 1;
        let mut buf = vec![0u8; size as usize];
        if CFStringGetCString(s, buf.as_mut_ptr() as *mut c_char, size, UTF8) == 0 {
            return None;
        }
        CStr::from_bytes_until_nul(&buf).ok().map(|c| c.to_string_lossy().into_owned())
    }

    /// A 32-bit property (UInt32 / pid_t) of an audio object.
    fn get_u32(object: AudioObjectID, selector: u32) -> Option<u32> {
        let mut value = 0u32;
        let mut size = std::mem::size_of::<u32>() as u32;
        let status = unsafe {
            AudioObjectGetPropertyData(object, &address(selector), 0, ptr::null(), &mut size, &mut value as *mut u32 as *mut c_void)
        };
        (status == 0).then_some(value)
    }

    /// The processes CoreAudio knows (macOS 14.2+; older: none).
    fn process_objects() -> Vec<AudioObjectID> {
        let addr = address(PROCESS_OBJECT_LIST);
        let mut size = 0u32;
        if unsafe { AudioObjectGetPropertyDataSize(SYSTEM_OBJECT, &addr, 0, ptr::null(), &mut size) } != 0 || size == 0 {
            return Vec::new();
        }
        let mut ids = vec![0 as AudioObjectID; size as usize / std::mem::size_of::<AudioObjectID>()];
        let mut size = (ids.len() * std::mem::size_of::<AudioObjectID>()) as u32;
        let status =
            unsafe { AudioObjectGetPropertyData(SYSTEM_OBJECT, &addr, 0, ptr::null(), &mut size, ids.as_mut_ptr() as *mut c_void) };
        if status != 0 {
            return Vec::new();
        }
        ids.truncate(size as usize / std::mem::size_of::<AudioObjectID>());
        ids
    }

    fn bundle_id(object: AudioObjectID) -> Option<String> {
        let mut s: CFStringRef = ptr::null();
        let mut size = std::mem::size_of::<CFStringRef>() as u32;
        let status = unsafe {
            AudioObjectGetPropertyData(
                object,
                &address(PROCESS_BUNDLE_ID),
                0,
                ptr::null(),
                &mut size,
                &mut s as *mut CFStringRef as *mut c_void,
            )
        };
        if status != 0 || s.is_null() {
            return None;
        }
        // The caller owns the returned CFString.
        let text = unsafe { cf_string(s) };
        unsafe { CFRelease(s) };
        text.filter(|t| !t.is_empty())
    }

    fn exe_path(pid: i32) -> Option<String> {
        let mut buf = vec![0u8; PROC_PIDPATHINFO_MAXSIZE];
        let n = unsafe { proc_pidpath(pid, buf.as_mut_ptr() as *mut c_void, buf.len() as u32) };
        (n > 0).then(|| String::from_utf8_lossy(&buf[..n as usize]).into_owned())
    }

    /// Apps recording from an input device right now: bundle ids, or the
    /// executable's path for processes without one.
    pub fn mic_users() -> Vec<String> {
        let own_pid = std::process::id();
        let mut out: Vec<String> = Vec::new();
        for object in process_objects() {
            if get_u32(object, PROCESS_IS_RUNNING_INPUT).unwrap_or(0) == 0 {
                continue;
            }
            let pid = get_u32(object, PROCESS_PID);
            if pid == Some(own_pid) {
                continue;
            }
            let key = match bundle_id(object) {
                Some(id) if id.eq_ignore_ascii_case(super::OWN_BUNDLE_ID) => continue,
                Some(id) => id,
                None => match pid.and_then(|p| exe_path(p as i32)) {
                    Some(path) => path,
                    None => continue,
                },
            };
            if !out.contains(&key) {
                out.push(key);
            }
        }
        out
    }

    /// Is the browser holding the mic also playing sound? (Its helpers count:
    /// Chrome plays from "com.google.Chrome.helper", Safari from WebKit's.)
    pub fn playing(call: &super::Call) -> bool {
        process_objects().into_iter().any(|object| {
            get_u32(object, PROCESS_IS_RUNNING_OUTPUT).unwrap_or(0) != 0
                && bundle_id(object).and_then(|id| super::call_app(&id)).is_some_and(|app| super::same_browser(Some(app), call.app))
        })
    }

    /// Titles of the on-screen windows of the browser holding the mic. None
    /// when none can be read: without the Screen Recording permission the
    /// names aren't shared.
    pub fn window_titles(call: &super::Call) -> Option<Vec<String>> {
        let mut titles = Vec::new();
        unsafe {
            let list = CGWindowListCopyWindowInfo(ON_SCREEN_ONLY | EXCLUDE_DESKTOP, 0);
            if list.is_null() {
                return None;
            }
            for i in 0..CFArrayGetCount(list) {
                let window = CFArrayGetValueAtIndex(list, i);
                if window.is_null() {
                    continue;
                }
                let owner = cf_string(CFDictionaryGetValue(window, kCGWindowOwnerName));
                if !super::same_browser(owner.as_deref().and_then(super::mac_window_app), call.app) {
                    continue;
                }
                if let Some(title) = cf_string(CFDictionaryGetValue(window, kCGWindowName)).filter(|t| !t.is_empty()) {
                    titles.push(title);
                }
            }
            CFRelease(list);
        }
        (!titles.is_empty()).then_some(titles)
    }
}

/// Linux: PipeWire (through pipewire-pulse) or PulseAudio lists the streams
/// recording and playing right now (`pactl`); window titles come from X11
/// (`wmctrl`, or `xprop`). Wayland windows don't share their titles, so there a
/// browser counts as a call while it records and plays at once. No pactl:
/// nothing is detected.
#[cfg(target_os = "linux")]
mod native {
    use std::collections::HashMap;
    use std::io::ErrorKind;
    use std::process::{Command, Stdio};
    use std::sync::atomic::{AtomicBool, Ordering};

    use super::linux_parse;

    pub const SUPPORTED: bool = true;

    /// pactl isn't installed: stop trying.
    static NO_PACTL: AtomicBool = AtomicBool::new(false);

    /// A tool's output, if it ran and succeeded. Err: the tool isn't installed.
    fn run(tool: &str, args: &[&str], c_locale: bool) -> Result<Option<String>, ()> {
        let mut cmd = Command::new(tool);
        cmd.args(args).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::null());
        if c_locale {
            cmd.env("LC_ALL", "C");
        }
        match cmd.output() {
            Ok(out) => Ok(out.status.success().then(|| String::from_utf8_lossy(&out.stdout).into_owned())),
            Err(e) if e.kind() == ErrorKind::NotFound => Err(()),
            Err(_) => Ok(None),
        }
    }

    /// `pactl list <what>` ("source-outputs", "sink-inputs"): JSON, else text.
    fn pactl_streams(what: &str) -> Vec<linux_parse::Stream> {
        if NO_PACTL.load(Ordering::Relaxed) {
            return Vec::new();
        }
        match run("pactl", &["--format=json", "list", what], true) {
            Err(()) => {
                eprintln!("[calls] pactl isn't installed: calls can't be detected");
                NO_PACTL.store(true, Ordering::Relaxed);
                Vec::new()
            }
            Ok(json) => match json.as_deref().and_then(linux_parse::pactl_json) {
                Some(streams) => streams,
                None => match run("pactl", &["list", what], true) {
                    Ok(Some(text)) => linux_parse::pactl_text(&text),
                    _ => Vec::new(),
                },
            },
        }
    }

    /// Apps recording right now, by executable name ("zoom", "chrome").
    pub fn mic_users() -> Vec<String> {
        linux_parse::stream_keys(&pactl_streams("source-outputs"), std::process::id())
    }

    /// Is the browser holding the mic also playing sound (not paused)?
    pub fn playing(call: &super::Call) -> bool {
        let streams: Vec<_> = pactl_streams("sink-inputs").into_iter().filter(|s| !s.corked).collect();
        linux_parse::stream_keys(&streams, std::process::id())
            .iter()
            .any(|key| super::same_browser(super::call_app(key), call.app))
    }

    /// Which call app a process is, by its executable.
    fn process_app(pid: u32) -> Option<&'static str> {
        let exe = std::fs::read_link(format!("/proc/{pid}/exe"))
            .ok()
            .and_then(|p| p.file_name().map(|n| n.to_string_lossy().trim_end_matches(" (deleted)").to_string()));
        let name = exe.or_else(|| std::fs::read_to_string(format!("/proc/{pid}/comm")).ok().map(|s| s.trim().to_string()))?;
        super::call_app(&name)
    }

    /// X11 windows: (pid, title).
    fn x11_windows() -> Vec<(u32, String)> {
        if let Ok(Some(out)) = run("wmctrl", &["-lp"], false) {
            return linux_parse::wmctrl(&out);
        }
        let Ok(Some(list)) = run("xprop", &["-root", "_NET_CLIENT_LIST"], false) else { return Vec::new() };
        linux_parse::client_list(&list)
            .iter()
            .take(200)
            .filter_map(|id| match run("xprop", &["-id", id, "_NET_WM_PID", "_NET_WM_NAME", "WM_NAME"], false) {
                Ok(Some(out)) => linux_parse::xprop_window(&out),
                _ => None,
            })
            .collect()
    }

    /// Titles of the browser's windows (X11 and XWayland only). None when it
    /// has none there: a Wayland window, or wmctrl/xprop isn't installed.
    pub fn window_titles(call: &super::Call) -> Option<Vec<String>> {
        std::env::var_os("DISPLAY")?;
        let mut apps: HashMap<u32, Option<&'static str>> = HashMap::new();
        let titles: Vec<String> = x11_windows()
            .into_iter()
            .filter(|(pid, _)| super::same_browser(*apps.entry(*pid).or_insert_with(|| process_app(*pid)), call.app))
            .map(|(_, title)| title)
            .collect();
        (!titles.is_empty()).then_some(titles)
    }
}

/// Other systems: no detection.
#[cfg(not(any(windows, target_os = "macos", target_os = "linux")))]
mod native {
    pub const SUPPORTED: bool = false;
    pub fn window_titles(_call: &super::Call) -> Option<Vec<String>> {
        None
    }
    pub fn playing(_call: &super::Call) -> bool {
        false
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
    fn recognises_mac_bundle_ids_and_their_helpers() {
        for (key, app) in [
            ("us.zoom.xos", "Zoom"),
            ("com.microsoft.teams2", "Teams"),
            ("com.microsoft.teams", "Teams"),
            ("net.whatsapp.WhatsApp", "WhatsApp"),
            ("desktop.WhatsApp", "WhatsApp"),
            ("com.hnc.Discord", "Discord"),
            ("com.hnc.Discord.helper", "Discord"),
            ("com.tinyspeck.slackmacgap", "Slack"),
            ("Cisco-Systems.Spark", "Webex"),
            ("com.skype.skype", "Skype"),
            ("com.apple.FaceTime", "FaceTime"),
            ("com.google.Chrome", "Chrome"),
            ("com.google.Chrome.helper", "Chrome"),
            ("com.google.Chrome.helper.renderer", "Chrome"),
            ("com.microsoft.edgemac.helper", "Edge"),
            ("com.brave.Browser.helper", "Brave"),
            ("org.mozilla.firefox", "Firefox"),
            ("com.operasoftware.Opera", "Opera"),
            ("com.vivaldi.Vivaldi", "Vivaldi"),
            ("com.apple.Safari", "Safari"),
            ("com.apple.WebKit.GPU", "Safari"),
            ("/Applications/zoom.us.app/Contents/MacOS/zoom.us", "Zoom"),
        ] {
            assert_eq!(call_app(key), Some(app), "{key}");
        }
        for key in [
            "com.rajvee.voicedesk",
            "com.apple.VoiceMemos",
            "com.obsproject.obs-studio",
            "com.googlecode.iterm2",
            // Only a dot after the id makes a helper.
            "com.google.Chromecast",
            "us.zoom.xosfake",
            "/usr/local/bin/sox",
        ] {
            assert_eq!(call_app(key), None, "{key}");
        }
    }

    #[test]
    fn recognises_linux_executables() {
        for (key, app) in [
            ("zoom", "Zoom"),
            ("chrome", "Chrome"),
            ("chromium", "Chromium"),
            ("firefox", "Firefox"),
            ("firefox-bin", "Firefox"),
            ("Discord", "Discord"),
            ("slack", "Slack"),
            ("teams-for-linux", "Teams"),
            ("skypeforlinux", "Skype"),
            ("brave", "Brave"),
            ("opera", "Opera"),
            ("vivaldi-bin", "Vivaldi"),
            ("msedge", "Edge"),
            ("webex", "Webex"),
        ] {
            assert_eq!(call_app(key), Some(app), "{key}");
        }
        for key in ["voicedesk", "obs", "arecord", "pw-record", "audacity", "speech-dispatcher"] {
            assert_eq!(call_app(key), None, "{key}");
        }
    }

    #[test]
    fn browser_windows_by_owner() {
        assert_eq!(mac_window_app("Google Chrome"), Some("Chrome"));
        assert_eq!(mac_window_app("Safari"), Some("Safari"));
        assert_eq!(mac_window_app("Firefox Developer Edition"), Some("Firefox"));
        assert_eq!(mac_window_app("Brave Browser"), Some("Brave"));
        assert_eq!(mac_window_app("Finder"), None);
        assert!(same_browser(Some("Chrome"), "Chrome"));
        assert!(same_browser(Some("Chrome"), "Chromium"));
        assert!(!same_browser(Some("Firefox"), "Chrome"));
        assert!(!same_browser(None, "Safari"));
    }

    #[test]
    fn reads_pactl_json() {
        let json = r#"[
          {"index":81,"driver":"PipeWire","source":56,"corked":false,
           "properties":{"application.name":"ZOOM VoiceEngine","application.process.id":"4242",
                         "application.process.binary":"zoom","media.class":"Stream/Input/Audio"}},
          {"index":90,"driver":"PipeWire","source":56,
           "properties":{"application.name":"voicedesk","application.process.id":"777",
                         "application.process.binary":"voicedesk"}},
          {"index":91,"driver":"PipeWire","source":57,
           "properties":{"application.name":"Chromium","application.process.id":5000}}
        ]"#;
        let streams = linux_parse::pactl_json(json).unwrap();
        assert_eq!(streams.len(), 3);
        assert_eq!(
            streams[0],
            linux_parse::Stream { binary: "zoom".into(), name: "ZOOM VoiceEngine".into(), pid: Some(4242), corked: false }
        );
        assert_eq!(streams[2].pid, Some(5000));
        assert_eq!(linux_parse::stream_keys(&streams, 1), vec!["zoom".to_string(), "Chromium".to_string()]);
        assert!(linux_parse::pactl_json("Source Output #81").is_none());
        assert_eq!(linux_parse::pactl_json("[]"), Some(vec![]));
    }

    #[test]
    fn reads_pactl_text() {
        let text = "Source Output #81\n\tDriver: PipeWire\n\tOwner Module: n/a\n\tProperties:\n\
            \t\tapplication.name = \"Google Chrome\"\n\t\tapplication.process.id = \"5100\"\n\
            \t\tapplication.process.binary = \"chrome\"\n\t\tmedia.name = \"Say \\\"hi\\\"\"\n\
            Source Output #82\n\tProperties:\n\t\tapplication.name = \"Voice Desk\"\n\
            \t\tapplication.process.id = \"999\"\n\t\tapplication.process.binary = \"voicedesk\"\n\
            Source Output #83\n\tProperties:\n\t\tapplication.process.id = \"999\"\n\
            \t\tapplication.process.binary = \"zoom\"\n\
            Source Output #84\n\tProperties:\n\t\tapplication.process.binary = \"chrome\"\n";
        let streams = linux_parse::pactl_text(text);
        assert_eq!(streams.len(), 4);
        assert_eq!(
            streams[0],
            linux_parse::Stream { binary: "chrome".into(), name: "Google Chrome".into(), pid: Some(5100), corked: false }
        );
        // Ourselves (by name, and by process id 999), and Chrome only once.
        assert_eq!(linux_parse::stream_keys(&streams, 999), vec!["chrome".to_string()]);
    }

    #[test]
    fn reads_sink_inputs() {
        let json = r#"[
          {"index":12,"corked":false,"properties":{"application.process.binary":"chrome","application.process.id":"5100"}},
          {"index":13,"corked":true,"properties":{"application.process.binary":"firefox","application.process.id":"6200"}}
        ]"#;
        let streams = linux_parse::pactl_json(json).unwrap();
        assert_eq!((streams[0].corked, streams[1].corked), (false, true));
        let text = "Sink Input #12\n\tDriver: PipeWire\n\tCorked: no\n\tProperties:\n\
            \t\tapplication.process.binary = \"chrome\"\n\
            Sink Input #13\n\tCorked: yes\n\tProperties:\n\t\tapplication.process.binary = \"firefox\"\n";
        let streams = linux_parse::pactl_text(text);
        assert_eq!(streams.len(), 2);
        assert_eq!((streams[0].binary.as_str(), streams[0].corked), ("chrome", false));
        assert_eq!((streams[1].binary.as_str(), streams[1].corked), ("firefox", true));
    }

    #[test]
    fn browsers_without_readable_titles_count_while_playing() {
        let titles = |ts: &[&str]| ts.iter().map(|t| t.to_string()).collect::<Vec<_>>();
        let t0 = Instant::now();
        let s = Duration::from_secs;
        let mut since = None;
        // Titles readable: they decide at once, sound doesn't matter.
        assert!(browser_is_call(Some(&titles(&["Meet - abc-defg-hij - Google Chrome"])), || false, &mut since, t0));
        assert!(!browser_is_call(Some(&titles(&["Untitled document - Google Docs"])), || true, &mut since, t0));
        assert_eq!(since, None);
        // Unreadable (macOS without Screen Recording, Wayland): recording alone
        // (dictation) isn't a call; recording and playing is, once it lasts.
        assert!(!browser_is_call(None, || false, &mut since, t0));
        assert!(!browser_is_call(None, || true, &mut since, t0));
        assert!(!browser_is_call(None, || true, &mut since, t0 + s(10))); // voice search, a mic test
        assert!(browser_is_call(None, || true, &mut since, t0 + BROWSER_SUSTAIN));
        // The sound stopping starts the wait again.
        assert!(!browser_is_call(None, || false, &mut since, t0 + s(30)));
        assert!(!browser_is_call(None, || true, &mut since, t0 + s(32)));
        assert!(browser_is_call(None, || true, &mut since, t0 + s(32) + BROWSER_SUSTAIN));
    }

    #[test]
    fn reads_x11_window_lists() {
        let wm = "0x03a00003  0 4242   laptop Meet - abc-defg-hij - Google Chrome\n\
                  0x01200007 -1 0      laptop Desktop\n\
                  0x04400003  1 5151   N/A    Inbox  (3) — Mozilla Firefox\n\
                  garbage\n";
        assert_eq!(
            linux_parse::wmctrl(wm),
            vec![(4242, "Meet - abc-defg-hij - Google Chrome".to_string()), (5151, "Inbox  (3) — Mozilla Firefox".to_string())]
        );
        assert_eq!(
            linux_parse::client_list("_NET_CLIENT_LIST(WINDOW): window id # 0x1e00003, 0x2400003\n"),
            vec!["0x1e00003".to_string(), "0x2400003".to_string()]
        );
        assert!(linux_parse::client_list("_NET_CLIENT_LIST:  not found.\n").is_empty());
        let w = "_NET_WM_PID(CARDINAL) = 4242\n_NET_WM_NAME(UTF8_STRING) = \"Meet \\342\\200\\223 \\\"Sync\\\"\"\nWM_NAME(STRING) = \"old\"\n";
        assert_eq!(linux_parse::xprop_window(w), Some((4242, "Meet – \"Sync\"".to_string())));
        let w = "_NET_WM_PID(CARDINAL) = 7\n_NET_WM_NAME:  not found.\nWM_NAME(STRING) = \"Zoom Meeting\"\n";
        assert_eq!(linux_parse::xprop_window(w), Some((7, "Zoom Meeting".to_string())));
        assert_eq!(linux_parse::xprop_window("_NET_WM_PID:  not found.\nWM_NAME(STRING) = \"x\"\n"), None);
    }

    #[test]
    fn browser_titles_of_calls() {
        for t in [
            "Meet - abc-defg-hij - Google Chrome",
            "Meet – Weekly sync - Microsoft\u{200b} Edge",
            "(2) WhatsApp - Google Chrome",
            "Zoom Meeting - Brave",
            "Chat | Microsoft Teams - Google Chrome",
            "Meet – YouTube channel planning - Google Chrome",
        ] {
            assert!(is_call_title(t), "{t}");
        }
        for t in [
            "Untitled document - Google Docs - Google Chrome",
            "Online Mic Test - Google Chrome",
            "YouTube - Brave",
            // Videos and music that name a call app.
            "Zoom tutorial for beginners - YouTube - Google Chrome",
            "(3) Discord drama explained - YouTube — Mozilla Firefox",
            "Slack Off - Spotify",
            "Teams highlights | Microsoft Teams vs Slack - Twitch",
            // Plain words that used to match.
            "Around the World in 80 Days - Google Search - Google Chrome",
        ] {
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
    fn meetings_started_before_their_call_take_it_on() {
        let zoom = Call { key: "zoom".into(), app: "Zoom" };
        let teams = Call { key: "teams".into(), app: "Teams" };
        // Started before joining: no call yet, then the call that starts.
        assert_eq!(meeting_call(None, &[]), None);
        assert_eq!(meeting_call(None, std::slice::from_ref(&zoom)), Some("zoom".into()));
        // Already tied to a call: another call starting doesn't change it.
        assert_eq!(meeting_call(Some("zoom".into()), &[teams, zoom]), Some("zoom".into()));
        // Ended for good: tied to Zoom, Zoom released the mic → "call ended".
        assert_eq!(check_meeting(Some(CALL_END_GRACE), Duration::ZERO), MeetingCheck::CallEnded);
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
            let titles = super::native::exe_window_titles(exe);
            println!("{exe}: {} windows {:?}", titles.len(), titles.iter().take(3).collect::<Vec<_>>());
        }
        assert!(!super::native::exe_window_titles("code.exe").is_empty(), "VS Code is open, so it has a window");
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
