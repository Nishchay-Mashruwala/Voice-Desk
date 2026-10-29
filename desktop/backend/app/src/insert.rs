//! Put dictated text wherever the user's cursor is, in whichever app has focus.

use std::sync::mpsc;
use std::thread::sleep;
use std::time::Duration;

use anyhow::{anyhow, Result};
use enigo::{Direction, Enigo, Key, Keyboard, Settings};
use tauri::AppHandle;

fn enigo() -> Result<Enigo> {
    Enigo::new(&Settings::default()).map_err(|e| anyhow!("keyboard init failed: {e}"))
}

/// macOS only allows keyboard-layout lookups (enigo does one to find the V key)
/// on the main thread; from any other thread the OS kills the app. So every
/// keystroke goes through here.
fn on_main_thread<T: Send + 'static>(
    app: &AppHandle,
    f: impl FnOnce() -> Result<T> + Send + 'static,
) -> Result<T> {
    let (tx, rx) = mpsc::channel();
    app.run_on_main_thread(move || {
        let _ = tx.send(f());
    })?;
    rx.recv_timeout(Duration::from_secs(10))
        .map_err(|_| anyhow!("keyboard didn't respond"))?
}

/// The dictation hotkey's modifiers may still be physically held (push-to-talk),
/// which would turn Ctrl+V into Ctrl+Shift+V etc. Release them first.
fn release_modifiers(e: &mut Enigo) {
    for k in [Key::Shift, Key::Control, Key::Alt, Key::Meta] {
        let _ = e.key(k, Direction::Release);
    }
}

/// Blocking; call from a blocking thread, never the main thread.
pub fn insert_text(app: &AppHandle, text: &str, method: &str) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }

    if method == "type" {
        let text = text.to_string();
        return on_main_thread(app, move || {
            let mut e = enigo()?;
            release_modifiers(&mut e);
            e.text(&text).map_err(|err| anyhow!("typing failed: {err}"))
        });
    }

    // Clipboard paste: instant for long text and works in nearly every app.
    let mut cb = arboard::Clipboard::new()?;
    let previous = cb.get_text().ok();
    cb.set_text(text.to_string())?;
    sleep(Duration::from_millis(40));

    on_main_thread(app, || {
        let mut e = enigo()?;
        release_modifiers(&mut e);
        // Cmd+V on macOS, Ctrl+V everywhere else.
        let modifier = if cfg!(target_os = "macos") { Key::Meta } else { Key::Control };
        e.key(modifier, Direction::Press).map_err(|err| anyhow!("{err}"))?;
        let pasted = e.key(Key::Unicode('v'), Direction::Click);
        let _ = e.key(modifier, Direction::Release);
        pasted.map_err(|err| anyhow!("paste failed: {err}"))
    })?;

    // Give the target app time to read the clipboard before restoring it.
    sleep(Duration::from_millis(250));
    if let Some(prev) = previous {
        let _ = cb.set_text(prev);
    }
    Ok(())
}
