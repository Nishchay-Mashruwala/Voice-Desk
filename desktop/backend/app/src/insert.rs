//! Put dictated text wherever the user's cursor is, in whichever app has focus.

use std::thread::sleep;
use std::time::Duration;

use anyhow::{anyhow, Result};
use enigo::{Direction, Enigo, Key, Keyboard, Settings};

fn enigo() -> Result<Enigo> {
    Enigo::new(&Settings::default()).map_err(|e| anyhow!("keyboard init failed: {e}"))
}

/// The dictation hotkey's modifiers may still be physically held (push-to-talk),
/// which would turn Ctrl+V into Ctrl+Shift+V etc. Release them first.
fn release_modifiers(e: &mut Enigo) {
    for k in [Key::Shift, Key::Control, Key::Alt, Key::Meta] {
        let _ = e.key(k, Direction::Release);
    }
}

/// Blocking; call from a blocking thread.
pub fn insert_text(text: &str, method: &str) -> Result<()> {
    if text.is_empty() {
        return Ok(());
    }
    let mut e = enigo()?;
    release_modifiers(&mut e);

    if method == "type" {
        return e.text(text).map_err(|err| anyhow!("typing failed: {err}"));
    }

    // Clipboard paste: instant for long text and works in nearly every app.
    let mut cb = arboard::Clipboard::new()?;
    let previous = cb.get_text().ok();
    cb.set_text(text.to_string())?;
    sleep(Duration::from_millis(40));

    // Cmd+V on macOS, Ctrl+V everywhere else.
    let modifier = if cfg!(target_os = "macos") { Key::Meta } else { Key::Control };
    e.key(modifier, Direction::Press).map_err(|err| anyhow!("{err}"))?;
    let pasted = e.key(Key::Unicode('v'), Direction::Click);
    let _ = e.key(modifier, Direction::Release);
    pasted.map_err(|err| anyhow!("paste failed: {err}"))?;

    // Give the target app time to read the clipboard before restoring it.
    sleep(Duration::from_millis(250));
    if let Some(prev) = previous {
        let _ = cb.set_text(prev);
    }
    Ok(())
}
