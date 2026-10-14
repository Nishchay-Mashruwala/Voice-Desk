//! Search across Listen recordings, meetings (titles, summaries, transcripts)
//! and tasks.
//!
//! A plain case-insensitive scan: a few hundred recordings take milliseconds,
//! and unlike a separate full-text index it can't fall out of step with edits,
//! renames and conversions.

use serde::Serialize;

use crate::db::{Db, Segment};

/// Results per kind (newest first).
const MAX_PER_KIND: usize = 40;
/// Matching lines shown per meeting.
const MAX_LINES_PER_MEETING: usize = 3;

#[derive(Debug, Serialize, PartialEq)]
pub struct Hit {
    /// "recording" | "meeting" | "task"
    pub kind: &'static str,
    pub title: String,
    /// Text around the match; the match itself is `snippet[match_start..match_end]` (chars).
    pub snippet: String,
    pub match_start: usize,
    pub match_end: usize,
    pub created_at: String,
    /// Where to open it: a meeting (Meetings page) or a Listen recording, and when (s).
    pub meeting_id: Option<i64>,
    pub dictation_id: Option<i64>,
    pub at_s: Option<f64>,
}

fn lower(s: &str) -> Vec<char> {
    s.chars().flat_map(char::to_lowercase).collect()
}

/// Char position of `q` (already lowercased) in `text`, ignoring case.
fn find(text: &str, q: &[char]) -> Option<usize> {
    let t = lower(text);
    if q.is_empty() || t.len() < q.len() || t.len() != text.chars().count() {
        // Lowercasing changed the length (rare letters): fall back to an exact-length scan.
        let chars: Vec<char> = text.chars().collect();
        return (0..chars.len().saturating_sub(q.len()) + 1)
            .find(|&i| !q.is_empty() && chars[i..].iter().zip(q).all(|(a, b)| a.to_lowercase().eq(b.to_lowercase())));
    }
    (0..=t.len() - q.len()).find(|&i| t[i..i + q.len()] == *q)
}

/// ~`width` chars around the match, with "…" where cut.
fn snippet(text: &str, at: usize, len: usize, width: usize) -> (String, usize, usize) {
    let chars: Vec<char> = text.chars().collect();
    let start = at.saturating_sub(width / 3);
    let end = (at + len + width * 2 / 3).min(chars.len());
    let mut s: String = chars[start..end].iter().collect();
    let mut offset = start;
    if start > 0 {
        s = format!("…{s}");
        offset = start - 1;
    }
    if end < chars.len() {
        s.push('…');
    }
    (s, at - offset, at - offset + len)
}

/// When (s) the word at char position `at` of `text` was said, from timed words.
fn time_at(text: &str, at: usize, words: &[(String, f64)]) -> Option<f64> {
    let word_index = text.chars().take(at).collect::<String>().split_whitespace().count();
    // The match may start mid-word: the word it's in has the preceding count's index.
    let ends_mid_word = text.chars().nth(at.saturating_sub(1)).is_some_and(|c| !c.is_whitespace()) && at > 0;
    let i = if ends_mid_word { word_index.saturating_sub(1) } else { word_index };
    words.get(i).or(words.last()).map(|w| w.1)
}

pub fn search(db: &Db, query: &str) -> anyhow::Result<Vec<Hit>> {
    let q = lower(query.trim());
    if q.is_empty() {
        return Ok(Vec::new());
    }
    let mut out = Vec::new();

    let mut n = 0;
    for d in db.dictations(10_000)? {
        if n >= MAX_PER_KIND {
            break;
        }
        let Some(at) = find(&d.text, &q) else { continue };
        let words: Vec<(String, f64)> = d.words.as_array().into_iter().flatten()
            .filter_map(|w| Some((w["w"].as_str()?.to_string(), w["s"].as_f64()?)))
            .collect();
        let (snippet, match_start, match_end) = snippet(&d.text, at, q.len(), 120);
        out.push(Hit {
            kind: "recording",
            title: "Recording".into(),
            snippet,
            match_start,
            match_end,
            created_at: d.created_at.clone(),
            meeting_id: None,
            dictation_id: Some(d.id),
            at_s: time_at(&d.text, at, &words),
        });
        n += 1;
    }

    n = 0;
    for m in db.meetings()?.into_iter().filter(|m| m.kind == "meeting") {
        if n >= MAX_PER_KIND {
            break;
        }
        let mut lines = 0;
        let hit = |text: &str, at: usize, at_s: Option<f64>| {
            let (snippet, match_start, match_end) = snippet(text, at, q.len(), 120);
            Hit {
                kind: "meeting",
                title: m.title.clone(),
                snippet,
                match_start,
                match_end,
                created_at: m.started_at.clone(),
                meeting_id: Some(m.id),
                dictation_id: None,
                at_s,
            }
        };
        if let Some(at) = find(&m.title, &q) {
            out.push(hit(&m.title, at, None));
            lines += 1;
        }
        for s in db.transcript(m.id)? {
            if lines >= MAX_LINES_PER_MEETING {
                break;
            }
            let Some(at) = find(&s.text, &q) else { continue };
            let text = format!("{}: {}", s.speaker, s.text);
            let at_s = segment_time(&s, at);
            out.push(hit(&text, at + s.speaker.chars().count() + 2, Some(at_s)));
            lines += 1;
        }
        if lines == 0 {
            if let Some(at) = m.summary.as_deref().and_then(|s| find(s, &q)) {
                out.push(hit(m.summary.as_deref().unwrap_or_default(), at, None));
                lines += 1;
            }
        }
        n += (lines > 0) as usize;
    }

    n = 0;
    for t in db.tasks(None)? {
        if n >= MAX_PER_KIND {
            break;
        }
        let Some(at) = find(&t.description, &q) else { continue };
        let (snippet, match_start, match_end) = snippet(&t.description, at, q.len(), 160);
        let in_meeting = t.meeting_kind.as_deref() == Some("meeting");
        out.push(Hit {
            kind: "task",
            title: t.meeting_title.clone().unwrap_or_else(|| "Task".into()),
            snippet,
            match_start,
            match_end,
            created_at: t.created_at.clone(),
            meeting_id: if in_meeting { t.meeting_id } else { None },
            dictation_id: if in_meeting { None } else { t.dictation_id },
            at_s: None,
        });
        n += 1;
    }
    Ok(out)
}

fn segment_time(s: &Segment, at: usize) -> f64 {
    let words: Vec<(String, f64)> = s.words.iter().flatten().map(|w| (w.w.clone(), w.s)).collect();
    time_at(&s.text, at, &words).unwrap_or(s.start)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::{NewTask, Word};

    fn db() -> Db {
        let dir = std::env::temp_dir().join(format!(
            "voicedesk-search-{}-{}",
            std::process::id(),
            std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        Db::open(&dir.join("t.db")).unwrap()
    }

    #[test]
    fn finds_words_in_recordings_meetings_and_tasks() {
        let db = db();
        let words = serde_json::json!([{"w": "send", "s": 1.0, "e": 1.3}, {"w": "the", "s": 1.3, "e": 1.4}, {"w": "Deck", "s": 1.4, "e": 2.0}]);
        let d = db.add_dictation("send the Deck", 2000, None, &words).unwrap();
        let m = db.create_meeting("Weekly sync", "meeting").unwrap();
        let w = |w: &str, s: f64| Word { w: w.into(), s, e: s + 0.3 };
        db.save_transcript(
            m,
            &[Segment { start: 5.0, end: 7.0, speaker: "Priya".into(), text: "update the deck please".into(), words: Some(vec![w("update", 5.0), w("the", 5.4), w("deck", 5.6), w("please", 6.1)]) }],
            7.0,
        )
        .unwrap();
        db.add_task(Some(m), &NewTask { description: "Update the deck".into(), assigned_by: None, due: None, quote: None }).unwrap();

        let hits = search(&db, "DECK").unwrap();
        let kinds: Vec<&str> = hits.iter().map(|h| h.kind).collect();
        assert_eq!(kinds, ["recording", "meeting", "task"]);
        assert_eq!((hits[0].dictation_id, hits[0].at_s), (Some(d.id), Some(1.4)));
        assert_eq!((hits[1].meeting_id, hits[1].at_s), (Some(m), Some(5.6)));
        let h = &hits[1];
        let marked: String = h.snippet.chars().skip(h.match_start).take(h.match_end - h.match_start).collect();
        assert_eq!(marked, "deck");
        assert!(search(&db, "  ").unwrap().is_empty());
        assert!(search(&db, "nothing like this").unwrap().is_empty());
    }

    #[test]
    fn matches_inside_words_and_other_scripts() {
        let db = db();
        db.add_dictation("તમે ગુજરાતી છો", 1000, None, &serde_json::Value::Null).unwrap();
        assert_eq!(search(&db, "ગુજરાતી").unwrap().len(), 1);
        db.add_dictation("rescheduling the call", 1000, None, &serde_json::Value::Null).unwrap();
        assert_eq!(search(&db, "schedul").unwrap().len(), 1);
    }
}
