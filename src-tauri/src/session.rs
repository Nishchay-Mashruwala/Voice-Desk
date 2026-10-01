//! The live listening session.
//!
//! While listening, the microphone streams to the speech engine, which cuts the
//! audio at pauses and sends back each phrase. Phrases are typed at the cursor
//! right away; voice commands ("Jarvis, pause") change what happens next.
//!
//! All engine results for a session are handled in order on one worker thread,
//! so typing never interleaves and commands apply exactly where they were said.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::Receiver;
use std::sync::Arc;
use std::time::Instant;

use base64::Engine as _;
use serde::Serialize;
use serde_json::{json, Value};
use tauri::{AppHandle, Emitter};

use crate::audio::{Recording, Sink, Source};
use crate::db::{Segment, Word};
use crate::{insert, overlay, pipeline, Shared};

/// Cosine similarity above which a phrase counts as the user's voice.
/// Measured: the user ~0.35–0.75, other voices < 0.2.
pub const VOICE_THRESHOLD: f64 = 0.30;

pub struct Session {
    pub sid: u64,
    /// None until the microphone has opened, and again once stopping.
    mic: Option<Recording>,
    stopping: bool,
    /// false = paused: still listening for commands, but not typing.
    pub writing: bool,
    /// The engine has its model loaded and is transcribing.
    pub ready: bool,
    pub capture: Option<Capture>,
    started: Instant,
    /// The whole session is recorded so it can be played back from History.
    audio_path: std::path::PathBuf,
    /// Everything heard (except commands), and each word's timing + what happened to it.
    heard: Vec<String>,
    words: Vec<Value>,
    samples: Arc<AtomicU64>,
    /// Voice task recordings made in this session; linked to its recording at the end.
    captures: Vec<i64>,
}

impl Session {
    pub fn mic_level(&self) -> Option<f32> {
        self.mic.as_ref().map(|m| m.level())
    }
}

/// "Jarvis, record tasks": collect what's said until "Jarvis, tasks recorded".
pub struct Capture {
    pub id: i64,
    /// Stream time (s) when capture started; the system recording starts here too.
    start_s: f64,
    system: Option<Recording>,
    me: Vec<Segment>,
    resume_writing: bool,
}

pub enum Work {
    Utterance(Value),
    Ready(u64),
    Failed(u64, String),
    Finalize(u64),
}

#[derive(Serialize, Clone)]
pub struct Status {
    /// idle | starting | listening | paused | stopping
    pub state: &'static str,
    pub capturing: bool,
    /// Task recordings still being turned into tasks.
    pub processing: u64,
    pub assistant_name: String,
    /// Seconds since listening started (for the overlay's timer).
    pub listening_s: Option<f64>,
    /// A meeting being recorded.
    pub meeting: Option<MeetingBar>,
    /// A call is on: the app the overlay offers to transcribe ("Zoom").
    pub call_prompt: Option<String>,
}

#[derive(Serialize, Clone)]
pub struct MeetingBar {
    pub id: i64,
    pub elapsed_s: f64,
}

pub fn status(st: &Shared) -> Status {
    let name = st.db.settings().map(|s| s.assistant_name).unwrap_or_default();
    let processing = st.processing.load(Ordering::Relaxed);
    let g = st.session.lock().unwrap();
    let (state, capturing) = match g.as_ref() {
        None => ("idle", false),
        Some(s) if s.stopping => ("stopping", s.capture.is_some()),
        Some(s) if !s.ready => ("starting", s.capture.is_some()),
        Some(s) if s.capture.is_some() => ("listening", true),
        Some(s) if s.writing => ("listening", false),
        Some(_) => ("paused", false),
    };
    let listening_s = g.as_ref().map(|s| s.started.elapsed().as_secs_f64());
    drop(g);
    let meeting = st
        .meeting
        .lock()
        .unwrap()
        .as_ref()
        .map(|m| MeetingBar { id: m.id, elapsed_s: m.started.elapsed().as_secs_f64() });
    let call_prompt = st.call_prompt.lock().unwrap().as_ref().map(|c| c.app.to_string());
    Status { state, capturing, processing, assistant_name: name, listening_s, meeting, call_prompt }
}

/// Tell the UI and overlay about the current state.
///
/// Updates can be triggered from several threads at once; running them all on
/// the main thread, and reading the state only when each one runs, means the
/// UI always ends up showing the latest state (never a stale one that
/// happened to arrive last).
pub fn emit_status(app: &AppHandle, st: &Shared) {
    let (app2, st2) = (app.clone(), st.clone());
    let _ = app.run_on_main_thread(move || {
        let s = status(&st2);
        let _ = app2.emit("session-status", &s);
        if s.state != "idle" || s.meeting.is_some() || s.call_prompt.is_some() {
            overlay::show(&app2, &st2);
        } else {
            overlay::hide(&app2, &st2);
        }
    });
}

fn notice(app: &AppHandle, message: impl Into<String>) {
    let _ = app.emit("session-notice", json!({ "message": message.into() }));
}

/// Copy the keys of `extra` into `target` (both JSON objects).
pub fn merge_json(target: &mut Value, extra: Value) {
    if let (Some(t), Value::Object(e)) = (target.as_object_mut(), extra) {
        t.extend(e);
    }
}

pub fn is_active(st: &Shared) -> bool {
    st.session.lock().unwrap().is_some()
}

/// Start listening. Speech is typed at the cursor as you talk.
fn start_listening(app: &AppHandle, st: &Shared) -> Result<(), String> {
    if is_active(st) {
        return Ok(());
    }
    let settings = st.db.settings().map_err(|e| e.to_string())?;
    let sid = st.next_sid.fetch_add(1, Ordering::Relaxed);
    let profile = st.voice_profile_path();
    let samples = Arc::new(AtomicU64::new(0));
    let audio_path = st
        .recordings_dir()
        .join(format!("listen-{}.wav", chrono::Local::now().format("%Y%m%d-%H%M%S")));

    // Register the session first: with the model already loaded, the engine's
    // "ready" can arrive before the microphone has finished opening.
    *st.session.lock().unwrap() = Some(Session {
        sid,
        mic: None,
        stopping: false,
        writing: true,
        ready: false,
        capture: None,
        started: Instant::now(),
        audio_path: audio_path.clone(),
        heard: Vec::new(),
        words: Vec::new(),
        samples: samples.clone(),
        captures: Vec::new(),
    });
    emit_status(app, st);
    let fail = |msg: String| {
        *st.session.lock().unwrap() = None;
        emit_status(app, st);
        msg
    };

    // Register the stream before any audio is sent so the engine knows the sid.
    let mut args = json!({
        "sid": sid,
        "model": settings.whisper_model,
        "device": settings.whisper_device,
        "language": settings.language,
        "vocabulary": settings.whisper_vocabulary(),
        "wake_name": settings.assistant_name,
        "commands": settings.commands(),
        "voice_profile": profile.exists().then_some(&profile),
        "silence_ms": settings.silence_ms,
        // Downloads the Hindi/Gujarati model (gated) on first use.
        "hf_token": settings.hf_token,
    });
    merge_json(&mut args, settings.language_options());
    let reply = st.engine.start_request("stream_start", args, None).map_err(|e| fail(e.to_string()))?;

    let engine = st.engine.clone();
    let counter = samples.clone();
    let on_chunk = Box::new(move |pcm: &[i16]| {
        counter.fetch_add(pcm.len() as u64, Ordering::Relaxed);
        let bytes: Vec<u8> = pcm.iter().flat_map(|s| s.to_le_bytes()).collect();
        let b64 = base64::engine::general_purpose::STANDARD.encode(bytes);
        let _ = engine.send(&json!({ "cmd": "audio", "sid": sid, "pcm": b64 }));
    });
    let mic = match Recording::start(Source::Microphone, Sink::Live(on_chunk, Some(audio_path))) {
        Ok(m) => m,
        Err(e) => {
            let _ = st.engine.start_request("stream_stop", json!({ "sid": sid }), None);
            return Err(fail(format!("Microphone error: {e}")));
        }
    };
    if let Some(s) = st.session.lock().unwrap().as_mut().filter(|s| s.sid == sid) {
        s.mic = Some(mic);
    }

    eprintln!("[session] {sid} started");
    let tx = st.work.clone();
    tauri::async_runtime::spawn(async move {
        if let Err(e) = crate::engine::Engine::wait(reply).await {
            let _ = tx.send(Work::Failed(sid, e.to_string()));
        }
    });
    emit_status(app, st);
    Ok(())
}

/// Stop listening. The last phrase is still typed before the session ends.
pub fn stop(app: &AppHandle, st: &Shared) {
    let (sid, mic) = {
        let mut g = st.session.lock().unwrap();
        let Some(s) = g.as_mut() else { return };
        if s.stopping {
            return;
        }
        s.stopping = true;
        (s.sid, s.mic.take())
    };
    eprintln!("[session] {sid} stopping");
    emit_status(app, st);
    let st2 = st.clone();
    tauri::async_runtime::spawn(async move {
        if let Some(mic) = mic {
            let _ = tauri::async_runtime::spawn_blocking(move || mic.stop()).await;
        }
        // The engine replies after it has emitted the final phrase, and the
        // Finalize work item queues behind it, so nothing said is lost.
        if let Ok(rx) = st2.engine.start_request("stream_stop", json!({ "sid": sid }), None) {
            let _ = crate::engine::Engine::wait(rx).await;
        }
        let _ = st2.work.send(Work::Finalize(sid));
    });
}

/// The shortcut, mic button or tray. During a call (the overlay offering
/// "Transcribe Meeting") it starts the meeting recording, like the button;
/// while a meeting is recorded it stops it; otherwise it starts/stops listening.
pub fn toggle(app: &AppHandle, st: &Shared) -> Result<(), String> {
    if is_active(st) {
        stop(app, st);
        Ok(())
    } else if st.meeting.lock().unwrap().is_some() {
        let (app, st) = (app.clone(), st.clone());
        tauri::async_runtime::spawn(async move {
            if let Err(e) = crate::end_meeting(&app, &st).await {
                notice(&app, e);
            }
        });
        Ok(())
    } else {
        start(app, st)
    }
}

/// Start listening (push-to-talk press too): during a call, record the meeting instead.
pub fn start(app: &AppHandle, st: &Shared) -> Result<(), String> {
    if st.meeting.lock().unwrap().is_some() {
        return Ok(()); // already recording the meeting: it hears everything
    }
    if st.call_prompt.lock().unwrap().is_some() {
        return crate::accept_call(app, st);
    }
    start_listening(app, st)
}

pub fn set_writing(app: &AppHandle, st: &Shared, on: bool) {
    {
        let mut g = st.session.lock().unwrap();
        let Some(s) = g.as_mut() else { return };
        match s.capture.as_mut() {
            // While recording tasks nothing is typed; apply once recording ends.
            Some(c) => {
                c.resume_writing = on;
                notice(app, if on { "Typing will resume after task recording" } else { "Typing paused" });
            }
            None => s.writing = on,
        }
    }
    emit_status(app, st);
}

pub fn start_capture(app: &AppHandle, st: &Shared) -> Result<(), String> {
    {
        let mut g = st.session.lock().unwrap();
        let Some(s) = g.as_mut() else { return Err("Start listening first".into()) };
        if s.capture.is_some() || s.stopping {
            return Ok(());
        }
        let title = format!("Task recording · {}", chrono::Local::now().format("%b %d, %H:%M"));
        let id = st.db.create_meeting(&title, "capture").map_err(|e| e.to_string())?;
        let (_, sys_path) = st.meeting_paths(id);
        // Others in a call are heard through the speakers; record them too.
        let system = Recording::to_file(Source::System, &sys_path)
            .map_err(|e| eprintln!("[capture] no system audio: {e}"))
            .ok();
        let start_s = s.samples.load(Ordering::Relaxed) as f64 / crate::audio::TARGET_RATE as f64;
        s.capture = Some(Capture { id, start_s, system, me: Vec::new(), resume_writing: s.writing });
        s.captures.push(id);
        s.writing = false;
    }
    let _ = app.emit("meetings-changed", ());
    emit_status(app, st);
    Ok(())
}

pub fn finish_capture(app: &AppHandle, st: &Shared) {
    let cap = {
        let mut g = st.session.lock().unwrap();
        let Some(s) = g.as_mut() else { return };
        let Some(cap) = s.capture.take() else { return };
        s.writing = cap.resume_writing;
        cap
    };
    process_capture(app, st, cap);
    emit_status(app, st);
}

pub fn toggle_capture(app: &AppHandle, st: &Shared) -> Result<(), String> {
    let capturing = st.session.lock().unwrap().as_ref().is_some_and(|s| s.capture.is_some());
    if capturing {
        finish_capture(app, st);
        Ok(())
    } else {
        start_capture(app, st)
    }
}

fn process_capture(app: &AppHandle, st: &Shared, cap: Capture) {
    st.processing.fetch_add(1, Ordering::Relaxed);
    let (app, st) = (app.clone(), st.clone());
    tauri::async_runtime::spawn(async move {
        if let Some(sys) = cap.system {
            let _ = tauri::async_runtime::spawn_blocking(move || sys.stop()).await;
        }
        let result = pipeline::process(app.clone(), st.clone(), cap.id, pipeline::Input::Capture(cap.me)).await;
        st.processing.fetch_sub(1, Ordering::Relaxed);
        let payload = match result {
            Ok(count) => json!({ "id": cap.id, "count": count }),
            Err(e) => json!({ "id": cap.id, "error": e }),
        };
        let _ = app.emit("capture-done", payload);
        emit_status(&app, &st);
    });
}

fn apply_command(app: &AppHandle, st: &Shared, cmd: &str) {
    match cmd {
        "stop" => stop(app, st),
        "pause" => set_writing(app, st, false),
        "resume" => set_writing(app, st, true),
        "record_tasks" => {
            if let Err(e) = start_capture(app, st) {
                notice(app, e);
            }
        }
        "tasks_recorded" => finish_capture(app, st),
        _ => {}
    }
}

enum TextAction {
    Type,
    Captured,
    Skip(&'static str),
}

impl TextAction {
    fn label(&self) -> &'static str {
        match self {
            TextAction::Type => "typed",
            TextAction::Captured => "captured",
            TextAction::Skip(why) => why,
        }
    }
}

fn handle_utterance(app: &AppHandle, st: &Shared, ev: &Value) {
    let sid = ev["sid"].as_u64().unwrap_or(0);
    if st.session.lock().unwrap().as_ref().map(|s| s.sid) != Some(sid) {
        return;
    }
    let settings = st.db.settings().unwrap_or_default();
    let has_profile = st.voice_profile_path().exists();
    let score = ev["score"].as_f64();
    // No profile: every voice is accepted. With a profile, too-short audio (no score) isn't.
    let is_me = if has_profile { score.is_some_and(|s| s >= VOICE_THRESHOLD) } else { true };
    let (start, end) = (ev["start"].as_f64().unwrap_or(0.0), ev["end"].as_f64().unwrap_or(0.0));

    let mut heard = Vec::new();
    for part in ev["parts"].as_array().into_iter().flatten() {
        if part["type"] == "command" {
            let cmd = part["command"].as_str().unwrap_or("");
            if has_profile && settings.voice_lock && !is_me {
                heard.push(json!({ "type": "command", "command": cmd, "status": "ignored" }));
                notice(app, format!("Ignored a “{}” command: it didn't sound like your voice", settings.assistant_name));
                continue;
            }
            heard.push(json!({ "type": "command", "command": cmd, "status": "done" }));
            apply_command(app, st, cmd);
            continue;
        }

        let text = part["text"].as_str().unwrap_or("").trim().to_string();
        if text.is_empty() {
            continue;
        }
        let action = {
            let mut g = st.session.lock().unwrap();
            match g.as_mut() {
                Some(s) if s.sid == sid => {
                    let action = if let Some(cap) = s.capture.as_mut() {
                        // Without headphones the mic also hears the call; the
                        // voice profile keeps other people's words out of "Me".
                        if is_me {
                            // Word times are stream-relative; the capture starts at start_s.
                            let at = |v: &Value| (v.as_f64().unwrap_or(0.0) - cap.start_s).max(0.0);
                            let words = part["words"]
                                .as_array()
                                .map(|ws| ws.iter().map(|w| Word { w: w["w"].as_str().unwrap_or("").into(), s: at(&w["s"]), e: at(&w["e"]) }).collect());
                            cap.me.push(Segment {
                                start: (start - cap.start_s).max(0.0),
                                end: (end - cap.start_s).max(0.0),
                                speaker: "Me".into(),
                                text: text.clone(),
                                words,
                            });
                            TextAction::Captured
                        } else {
                            TextAction::Skip("not your voice")
                        }
                    } else if !s.writing {
                        TextAction::Skip("paused")
                    } else if has_profile && settings.only_my_voice && !is_me {
                        TextAction::Skip("not your voice")
                    } else {
                        TextAction::Type
                    };
                    let status = action.label();
                    s.heard.push(text.clone());
                    for w in part["words"].as_array().into_iter().flatten() {
                        let mut w = w.clone();
                        w["st"] = json!(status);
                        s.words.push(w);
                    }
                    action
                }
                _ => TextAction::Skip("stopped"),
            }
        };
        let status = action.label();
        if let TextAction::Type = action {
            if let Err(e) = insert::insert_text(&format!("{text} "), &settings.insert_method) {
                notice(app, format!("Couldn't type: {e}"));
            }
        }
        heard.push(json!({ "type": "text", "text": text, "status": status }));
    }
    let _ = app.emit("heard", json!({ "parts": heard, "score": score }));
}

fn finalize(app: &AppHandle, st: &Shared, sid: u64) {
    let session = {
        let mut g = st.session.lock().unwrap();
        if g.as_ref().map(|s| s.sid) != Some(sid) {
            return;
        }
        g.take().unwrap()
    };
    if let Some(cap) = session.capture {
        process_capture(app, st, cap);
    }
    let text = session.heard.join(" ");
    if text.trim().is_empty() {
        // Nothing was said: don't keep an empty recording.
        let _ = std::fs::remove_file(&session.audio_path);
    } else {
        let audio = session.audio_path.exists().then_some(session.audio_path.as_path());
        let duration = session.started.elapsed().as_millis() as i64;
        match st.db.add_dictation(&text, duration, audio, &Value::Array(session.words)) {
            Ok(mut d) => {
                if !session.captures.is_empty() {
                    if let Err(e) = st.db.link_captures(d.id, &session.captures) {
                        eprintln!("[session] could not link task recordings: {e}");
                    }
                    d = st.db.dictations(1).ok().and_then(|v| v.into_iter().next()).unwrap_or(d);
                }
                let _ = app.emit("dictation-added", &d);
            }
            Err(e) => eprintln!("[session] could not save history: {e}"),
        }
    }
    emit_status(app, st);
}

/// Runs for the app's lifetime, handling engine results in order.
pub fn worker(app: AppHandle, st: Shared, rx: Receiver<Work>) {
    for work in rx {
        match work {
            Work::Utterance(ev) => handle_utterance(&app, &st, &ev),
            Work::Ready(sid) => {
                if let Some(s) = st.session.lock().unwrap().as_mut().filter(|s| s.sid == sid) {
                    s.ready = true;
                }
                emit_status(&app, &st);
            }
            Work::Failed(sid, e) => {
                if st.session.lock().unwrap().as_ref().map(|s| s.sid) == Some(sid) {
                    notice(&app, format!("Speech engine problem: {e}"));
                    stop(&app, &st);
                    let _ = st.work.send(Work::Finalize(sid));
                }
            }
            Work::Finalize(sid) => finalize(&app, &st, sid),
        }
    }
}
