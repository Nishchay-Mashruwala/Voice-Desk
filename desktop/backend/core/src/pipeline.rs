//! Turning recordings into transcripts and tasks. Shared by meetings recorded
//! from the Meetings page and task recordings started by voice.

use serde_json::{json, Value};

use crate::db::Segment;
use crate::llm::Mode;
use crate::{err, Backend};

pub enum Input {
    /// Meetings page: transcribe the saved mic + system WAVs.
    Recording,
    /// "Jarvis, record tasks": the user's words were already transcribed live;
    /// only the system audio (others in a call) still needs transcribing.
    Capture(Vec<Segment>),
    /// Keep the transcript, just find tasks again (e.g. after changing your name).
    Reextract,
}

/// Returns the number of tasks found.
pub async fn process(st: &Backend, id: i64, input: Input) -> Result<usize, String> {
    let result = run(st, id, input).await;
    // Processed: keep the recording as FLAC (lossless, ~1/3 of the WAV's size).
    let (mic, sys) = st.meeting_paths(id);
    let wavs: Vec<_> = [mic, sys].into_iter().filter(|p| p.exists()).collect();
    if !wavs.is_empty() {
        let _ = st.engine.request("compress", json!({ "paths": wavs }), None).await;
    }
    if let Err(e) = &result {
        let _ = st.db.set_meeting_status(id, "error", Some(e));
    }
    st.emit("meetings-changed", Value::Null);
    st.emit("tasks-changed", Value::Null);
    result
}

async fn run(st: &Backend, id: i64, input: Input) -> Result<usize, String> {
    let progress = |stage: &str, pct: f64| {
        st.emit("meeting-progress", json!({ "id": id, "stage": stage, "pct": pct }));
    };
    let settings = st.db.settings().map_err(err)?;

    let (mic_path, sys_path) = st.meeting_paths(id);
    let mic_segments = match input {
        Input::Reextract => None,
        Input::Recording => Some(None),
        Input::Capture(me) => Some(Some(me)),
    };

    if let Some(mic_segments) = mic_segments {
        st.db.set_meeting_status(id, "transcribing", None).map_err(err)?;
        st.emit("meetings-changed", Value::Null);
        let events = st.events.clone();
        let on_event = Box::new(move |ev: &Value| match ev["event"].as_str() {
            // Transcription is the first 80% of the progress bar.
            Some("progress") => {
                events.emit(
                    "meeting-progress",
                    json!({ "id": id, "stage": ev["stage"], "pct": ev["pct"].as_f64().unwrap_or(0.0) * 0.8 }),
                );
            }
            Some("warning") => {
                events.emit("meeting-warning", json!({ "id": id, "message": ev["message"] }));
            }
            _ => {}
        });
        let profile = st.voice_profile_path();
        let capture = mic_segments.is_some();
        let mut args = json!({
            "mic_path": if capture { None } else { crate::recordings::recorded(&mic_path) },
            "mic_segments": mic_segments,
            "system_path": crate::recordings::recorded(&sys_path),
            "model": settings.whisper_model,
            "device": settings.device,
            "language": settings.language,
            "vocabulary": settings.whisper_vocabulary(),
            "hf_token": settings.hf_token,
            "voice_profile": profile.exists().then_some(&profile),
            "people": st.db.people().unwrap_or_default(),
        });
        crate::merge_json(&mut args, settings.language_options());
        let res = st.engine.request("meeting", args, Some(on_event)).await.map_err(err)?;
        let segments: Vec<Segment> = serde_json::from_value(res["segments"].clone()).map_err(err)?;
        // Words the user leaves out ("umm"); live captures were already filtered.
        let segments = crate::omit::Omit::new(&settings.omit_words).segments(segments);
        let duration = res["duration"].as_f64().unwrap_or(0.0);
        st.db.save_transcript(id, &segments, duration).map_err(err)?;
    }

    st.db.set_meeting_status(id, "extracting", None).map_err(err)?;
    st.emit("meetings-changed", Value::Null);
    progress("finding_tasks", 80.0);

    let segments = st.db.transcript(id).map_err(err)?;
    let meeting = st.db.meeting(id).map_err(err)?.ok_or("meeting not found")?;
    // Only the user spoke -> they were noting their own to-dos.
    let mode = if segments.iter().any(|s| s.speaker != "Me") {
        Mode::Meeting
    } else {
        Mode::SelfNotes
    };
    let extraction = st
        .llm
        .extract(&settings, &meeting.title, &segments, mode, |i, n| {
            progress("finding_tasks", 80.0 + 20.0 * i as f64 / (n as f64 + 1.0))
        })
        .await
        .map_err(err)?;
    st.db.save_summary(id, &extraction.summary).map_err(err)?;
    st.db.replace_meeting_tasks(id, &extraction.tasks).map_err(err)?;
    st.db.set_meeting_status(id, "done", None).map_err(err)?;
    progress("done", 100.0);
    Ok(extraction.tasks.len())
}
