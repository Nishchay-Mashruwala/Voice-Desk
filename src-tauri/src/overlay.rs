//! The small always-on-top control bar shown while listening.
//! It never takes keyboard focus, so typing keeps going to the user's app,
//! and it stays wherever the user drags it (remembered across restarts).

use tauri::{AppHandle, Manager, PhysicalPosition, WebviewWindow};

use crate::Shared;

const POS_KEY: &str = "overlay_pos";

fn window(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window("overlay")
}

/// Prepare the overlay window once at startup.
pub fn init(app: &AppHandle) {
    if let Some(w) = window(app) {
        native::strip_frame(&w);
    }
}

pub fn show(app: &AppHandle, st: &Shared) {
    let Some(w) = window(app) else { return };
    if native::is_visible(&w) {
        return;
    }
    place(&w, st);
    native::show_without_focus(&w);
}

pub fn hide(app: &AppHandle, st: &Shared) {
    let Some(w) = window(app) else { return };
    if native::is_visible(&w) {
        native::hide(&w);
        save(st);
    }
}

/// Switch between the full bar and the small bubble (logical pixels).
/// Grows/shrinks from the left edge, where the logo is.
pub fn resize(app: &AppHandle, width: f64, height: f64) {
    if let Some(w) = window(app) {
        let scale = w.scale_factor().unwrap_or(1.0);
        native::set_size(&w, (width * scale).round() as i32, (height * scale).round() as i32);
    }
}

/// Called when the window moves (the user dragged it).
pub fn moved(st: &Shared, pos: PhysicalPosition<i32>) {
    *st.overlay_pos.lock().unwrap() = Some((pos.x, pos.y));
}

pub fn save(st: &Shared) {
    if let Some((x, y)) = *st.overlay_pos.lock().unwrap() {
        let _ = st.db.set_value(POS_KEY, &format!("{x},{y}"));
    }
}

fn saved(st: &Shared) -> Option<(i32, i32)> {
    if let Some(p) = *st.overlay_pos.lock().unwrap() {
        return Some(p);
    }
    let raw = st.db.get_value(POS_KEY).ok().flatten()?;
    let (x, y) = raw.split_once(',')?;
    Some((x.trim().parse().ok()?, y.trim().parse().ok()?))
}

fn place(w: &WebviewWindow, st: &Shared) {
    let size = w.outer_size().unwrap_or_default();
    // Use the remembered spot if it's still on a connected screen.
    if let Some((x, y)) = saved(st) {
        let on_screen = w.available_monitors().unwrap_or_default().iter().any(|m| {
            let (p, s) = (m.position(), m.size());
            x >= p.x && y >= p.y && x + 30 <= p.x + s.width as i32 && y + 30 <= p.y + s.height as i32
        });
        if on_screen {
            native::set_position(w, x, y);
            return;
        }
    }
    // Default: bottom-centre of the primary screen, above the taskbar.
    if let Ok(Some(m)) = w.primary_monitor() {
        let (area, pos) = (m.size(), m.position());
        let x = pos.x + (area.width as i32 - size.width as i32) / 2;
        let y = pos.y + area.height as i32 - size.height as i32 - (90.0 * m.scale_factor()) as i32;
        native::set_position(w, x, y);
    }
}

/// Windows: manage the overlay with Win32 directly. Tauri's show() activates
/// the window (stealing the cursor from the user's app). And once shown this
/// way, Tauri's own move/resize calls must not be used either: they re-apply
/// Tauri's remembered "hidden" state and hide the window again.
#[cfg(windows)]
mod native {
    use std::ffi::c_void;
    use tauri::WebviewWindow;

    #[link(name = "user32")]
    extern "system" {
        fn ShowWindow(hwnd: *mut c_void, cmd: i32) -> i32;
        fn IsWindowVisible(hwnd: *mut c_void) -> i32;
        fn GetWindowLongPtrW(hwnd: *mut c_void, index: i32) -> isize;
        fn SetWindowLongPtrW(hwnd: *mut c_void, index: i32, value: isize) -> isize;
        fn SetWindowPos(hwnd: *mut c_void, after: *mut c_void, x: i32, y: i32, cx: i32, cy: i32, flags: u32) -> i32;
    }

    const SW_HIDE: i32 = 0;
    const SW_SHOWNOACTIVATE: i32 = 4;
    const GWL_STYLE: i32 = -16;
    const GWL_EXSTYLE: i32 = -20;
    const WS_POPUP: isize = 0x8000_0000u32 as i32 as isize;
    const WS_FRAME: isize = 0x00C0_0000 | 0x0004_0000 | 0x0008_0000 | 0x0002_0000 | 0x0001_0000; // caption, sizing border, system menu, min/max
    const WS_EX_NOACTIVATE: isize = 0x0800_0000;
    const WS_EX_TOOLWINDOW: isize = 0x0000_0080; // no taskbar button, no Alt+Tab entry
    const WS_EX_APPWINDOW: isize = 0x0004_0000;
    const SWP_NOSIZE: u32 = 0x0001;
    const SWP_NOMOVE: u32 = 0x0002;
    const SWP_NOZORDER: u32 = 0x0004;
    const SWP_NOACTIVATE: u32 = 0x0010;
    const SWP_FRAMECHANGED: u32 = 0x0020;
    const SWP_FLAGS: u32 = SWP_NOSIZE | SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED;

    fn hwnd(w: &WebviewWindow) -> Option<*mut c_void> {
        w.hwnd().ok().map(|h| h.0 as *mut c_void)
    }

    /// No title bar or borders, never activated, not in the taskbar.
    pub fn strip_frame(w: &WebviewWindow) {
        let Some(h) = hwnd(w) else { return };
        unsafe {
            let style = GetWindowLongPtrW(h, GWL_STYLE);
            SetWindowLongPtrW(h, GWL_STYLE, (style & !WS_FRAME) | WS_POPUP);
            let ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
            SetWindowLongPtrW(h, GWL_EXSTYLE, (ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW) & !WS_EX_APPWINDOW);
            SetWindowPos(h, std::ptr::null_mut(), 0, 0, 0, 0, SWP_FLAGS);
        }
    }

    pub fn show_without_focus(w: &WebviewWindow) {
        let Some(h) = hwnd(w) else { return };
        strip_frame(w);
        unsafe {
            ShowWindow(h, SW_SHOWNOACTIVATE);
        }
    }

    pub fn hide(w: &WebviewWindow) {
        if let Some(h) = hwnd(w) {
            unsafe {
                ShowWindow(h, SW_HIDE);
            }
        }
    }

    pub fn is_visible(w: &WebviewWindow) -> bool {
        hwnd(w).is_some_and(|h| unsafe { IsWindowVisible(h) != 0 })
    }

    pub fn set_position(w: &WebviewWindow, x: i32, y: i32) {
        if let Some(h) = hwnd(w) {
            unsafe {
                SetWindowPos(h, std::ptr::null_mut(), x, y, 0, 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
    }

    pub fn set_size(w: &WebviewWindow, width: i32, height: i32) {
        if let Some(h) = hwnd(w) {
            unsafe {
                SetWindowPos(h, std::ptr::null_mut(), 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
            }
        }
    }
}

/// macOS/Linux: the window is created undecorated and non-focusable, so the
/// regular Tauri calls already behave.
#[cfg(not(windows))]
mod native {
    use tauri::WebviewWindow;

    pub fn strip_frame(_w: &WebviewWindow) {}

    pub fn show_without_focus(w: &WebviewWindow) {
        let _ = w.show();
    }

    pub fn hide(w: &WebviewWindow) {
        let _ = w.hide();
    }

    pub fn is_visible(w: &WebviewWindow) -> bool {
        w.is_visible().unwrap_or(false)
    }

    pub fn set_position(w: &WebviewWindow, x: i32, y: i32) {
        let _ = w.set_position(tauri::PhysicalPosition::new(x, y));
    }

    pub fn set_size(w: &WebviewWindow, width: i32, height: i32) {
        let _ = w.set_size(tauri::PhysicalSize::new(width as u32, height as u32));
    }
}
