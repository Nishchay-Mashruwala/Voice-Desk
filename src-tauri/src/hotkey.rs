//! The global shortcut: single, double, long press or push-to-talk.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use serde_json::json;
use tauri::{AppHandle, Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};

use crate::db::Settings;
use crate::{err, session, Shared};

/// Tracks presses for the double-press and long-press shortcut modes.
#[derive(Default)]
struct KeyState {
    last_press: Option<Instant>,
    /// Incremented on every press/release; a pending long-press only fires if unchanged.
    generation: u64,
}

const DOUBLE_PRESS_WINDOW: Duration = Duration::from_millis(450);

pub fn register_hotkey(app: &AppHandle, settings: &Settings) -> Result<(), String> {
    let gs = app.global_shortcut();
    gs.unregister_all().map_err(err)?;
    let mode = settings.dictation_mode.clone();
    // Saving settings registers the shortcut again, so this stays current.
    let meeting = settings.shortcut_starts == "meeting";
    let long_press = Duration::from_secs_f32(settings.long_press_s.clamp(0.5, 10.0));
    let keys = Arc::new(Mutex::new(KeyState::default()));
    gs.on_shortcut(settings.dictation_hotkey.as_str(), move |app, _shortcut, event| {
        let pressed = event.state() == ShortcutState::Pressed;
        // Starting opens the microphone: done on the session's own thread, in
        // press order, so the main thread (the windows) never waits for a device.
        let act = |f: fn(&AppHandle, &Shared) -> Result<(), String>| {
            let (app, st) = (app.clone(), app.state::<Shared>().inner().clone());
            session::in_order(move || {
                if let Err(e) = f(&app, &st) {
                    let _ = app.emit("session-notice", json!({ "message": e }));
                }
            });
        };
        match (mode.as_str(), pressed) {
            // Settings → "The shortcut starts": a meeting recording isn't held
            // down like push-to-talk, so in that case a press starts/stops it.
            ("hold", true) if meeting => act(session::shortcut),
            ("hold", false) if meeting => {}
            // Push-to-talk: listen only while the keys are held.
            ("hold", true) => act(session::start),
            ("hold", false) => act(|app, st| {
                session::stop(app, st);
                Ok(())
            }),
            // Double-press to start, double-press to stop.
            ("double", true) => {
                let mut k = keys.lock().unwrap();
                let now = Instant::now();
                if k.last_press.is_some_and(|t| now - t <= DOUBLE_PRESS_WINDOW) {
                    k.last_press = None;
                    drop(k);
                    act(session::shortcut);
                } else {
                    k.last_press = Some(now);
                }
            }
            // Hold for N seconds to start, again to stop (hard to trigger by accident).
            ("long", true) => {
                let generation = {
                    let mut k = keys.lock().unwrap();
                    k.generation += 1;
                    k.generation
                };
                let (app, keys) = (app.clone(), keys.clone());
                std::thread::spawn(move || {
                    std::thread::sleep(long_press);
                    if keys.lock().unwrap().generation == generation {
                        let st = app.state::<Shared>().inner().clone();
                        if let Err(e) = session::shortcut(&app, &st) {
                            let _ = app.emit("session-notice", json!({ "message": e }));
                        }
                    }
                });
            }
            ("long", false) => {
                keys.lock().unwrap().generation += 1; // released early: cancel
            }
            // Default: press once to start, once to stop.
            (_, true) => act(session::shortcut),
            (_, false) => {}
        }
    })
    .map_err(|e| format!("Could not register hotkey '{}': {e}", settings.dictation_hotkey))
}
