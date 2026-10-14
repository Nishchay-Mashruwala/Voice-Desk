//! Transcripts for showing and fixing: word timings after an edit, and where
//! each task was said (underlined, and where "play from this task" starts).

use serde::Serialize;
use serde_json::{json, Map, Value};

use crate::db::{Db, Dictation, Segment, Word};

/// A task underlined in a transcript.
#[derive(Debug, Clone, Serialize)]
pub struct TaskMark {
    pub description: String,
    pub quote: Option<String>,
    /// When its quote starts in the recording, or None if it isn't found.
    pub at_s: Option<f64>,
}

/// A transcript line as shown: always with word timings, which task each
/// word belongs to, and what can be done with its speaker.
#[derive(Debug, Clone, Serialize)]
pub struct SegmentView {
    pub start: f64,
    pub end: f64,
    pub speaker: String,
    pub text: String,
    pub words: Vec<Word>,
    /// For each word, the task (index into the transcript's `tasks`) it was said for.
    pub word_tasks: Vec<Option<usize>>,
    /// The user's own line.
    pub mine: bool,
    /// The speaker can be renamed (everyone but the user).
    pub renamable: bool,
    /// The speaker has the engine's automatic name ("Speaker 2", "Others"), not a person's.
    pub automatic: bool,
}

#[derive(Debug, Clone, Serialize)]
pub struct MeetingTranscript {
    pub segments: Vec<SegmentView>,
    pub tasks: Vec<TaskMark>,
}

/// The user's own lines; never renamed.
pub const ME: &str = "Me";

/// A speaker name the engine gave ("Speaker 2", "Others"), not a person's.
pub fn is_automatic_speaker(name: &str) -> bool {
    name == "Others" || name.strip_prefix("Speaker ").is_some_and(|n| !n.is_empty() && n.chars().all(|c| c.is_ascii_digit()))
}

// --------------------------------------------------------------------------- //
// Comparing words
// --------------------------------------------------------------------------- //

/// Combining marks (vowel signs, viramas...) outside what `is_alphanumeric`
/// keeps, so Hindi/Gujarati words still compare whole. Punctuation in those
/// scripts (dandas, abbreviation signs, the rupee sign) is left out.
fn is_mark(c: char) -> bool {
    matches!(c as u32,
        0x0300..=0x036F | 0x1AB0..=0x1AFF | 0x1DC0..=0x1DFF | 0x20D0..=0x20FF | 0xFE20..=0xFE2F)
        || (matches!(c as u32, 0x0900..=0x0DFF) && !matches!(c as u32, 0x0964 | 0x0965 | 0x0970 | 0x0AF0 | 0x0AF1))
}

/// A word compared ignoring case and punctuation.
pub fn norm(w: &str) -> String {
    w.to_lowercase().chars().filter(|&c| c.is_alphanumeric() || is_mark(c)).collect()
}

/// A quote's words. The task AI sometimes keeps the transcript's "Name:" in front; drop it.
fn quote_tokens(quote: Option<&str>) -> Vec<String> {
    let q = quote.unwrap_or("").trim_start();
    let name_len = q.chars().take_while(|c| !c.is_whitespace() && *c != ':').count();
    let rest = &q[q.char_indices().nth(name_len).map_or(q.len(), |(i, _)| i)..];
    let q = match rest.strip_prefix(':') {
        Some(after) if (1..=30).contains(&name_len) && after.starts_with(char::is_whitespace) => after,
        _ => q,
    };
    q.split_whitespace().map(norm).filter(|t| !t.is_empty()).collect()
}

/// How many quote words match in a row from word `i` on, and where the match
/// ends. Words with no letters (punctuation only) inside the match are skipped.
fn match_at(tokens: &[String], q: &[String], i: usize) -> (usize, usize) {
    let (mut j, mut k) = (i, 0);
    while j < tokens.len() && k < q.len() {
        if tokens[j].is_empty() {
            j += 1;
        } else if tokens[j] == q[k] {
            j += 1;
            k += 1;
        } else {
            break;
        }
    }
    (k, j)
}

/// For each word, the task (index into `quotes`) it was said for.
pub fn task_of_words(words: &[&str], quotes: &[Option<&str>]) -> Vec<Option<usize>> {
    let mut out = vec![None; words.len()];
    let tokens: Vec<String> = words.iter().map(|w| norm(w)).collect();
    for (t, quote) in quotes.iter().enumerate() {
        let q = quote_tokens(*quote);
        if q.is_empty() {
            continue;
        }
        for i in 0..tokens.len() {
            let (k, end) = match_at(&tokens, &q, i);
            if k == q.len() {
                out[i..end].iter_mut().for_each(|o| *o = Some(t));
                break;
            }
        }
    }
    out
}

/// When a quote starts in these timed words (word text, start), or None if it
/// isn't there. The task AI sometimes rewords the end of a quote, so failing an
/// exact match, the place where most of its opening words (3 or more) match wins.
pub fn quote_start(words: &[(&str, f64)], quote: Option<&str>) -> Option<f64> {
    let q = quote_tokens(quote);
    if q.is_empty() {
        return None;
    }
    let tokens: Vec<String> = words.iter().map(|(w, _)| norm(w)).collect();
    let mut best = None;
    let mut best_k = q.len().min(3) - 1;
    for i in 0..tokens.len() {
        if tokens[i].is_empty() {
            continue;
        }
        let (k, _) = match_at(&tokens, &q, i);
        if k == q.len() {
            return Some(words[i].1);
        }
        if k > best_k {
            best = Some(i);
            best_k = k;
        }
    }
    best.map(|i| words[i].1)
}

// --------------------------------------------------------------------------- //
// Word timings
// --------------------------------------------------------------------------- //

/// Older transcripts have no word timings: spread the line's time over its words by length.
pub fn spread_words(s: &Segment) -> Vec<Word> {
    let parts: Vec<&str> = s.text.split_whitespace().collect();
    let total = parts.iter().map(|w| w.chars().count() + 1).sum::<usize>().max(1) as f64;
    let mut t = s.start;
    parts
        .into_iter()
        .map(|w| {
            let d = (s.end - s.start) * (w.chars().count() + 1) as f64 / total;
            let word = Word { w: w.into(), s: t, e: t + d };
            t += d;
            word
        })
        .collect()
}

fn round2(x: f64) -> f64 {
    (x * 100.0).round() / 100.0
}

/// Word timings for edited text. Words that didn't change keep their exact
/// times (matched in order, ignoring case and punctuation); new or changed
/// words share the time between their unchanged neighbours, or `start`/`end`.
/// Words are JSON objects {"w", "s", "e", ...}; other fields of kept words
/// (like "st", what happened to them) are kept too.
pub fn retime_words(old: &[Value], text: &str, start: f64, end: f64) -> Vec<Value> {
    let next: Vec<&str> = text.split_whitespace().collect();
    let a: Vec<String> = old.iter().map(|w| norm(w["w"].as_str().unwrap_or(""))).collect();
    let b: Vec<String> = next.iter().map(|w| norm(w)).collect();
    // Longest common subsequence: which new words are old words.
    let mut lcs = vec![vec![0usize; b.len() + 1]; a.len() + 1];
    for i in (0..a.len()).rev() {
        for j in (0..b.len()).rev() {
            lcs[i][j] =
                if !a[i].is_empty() && a[i] == b[j] { lcs[i + 1][j + 1] + 1 } else { lcs[i + 1][j].max(lcs[i][j + 1]) };
        }
    }
    let mut matched: Vec<Option<usize>> = vec![None; b.len()];
    let (mut i, mut j) = (0, 0);
    while i < a.len() && j < b.len() {
        if !a[i].is_empty() && a[i] == b[j] {
            matched[j] = Some(i);
            i += 1;
            j += 1;
        } else if lcs[i + 1][j] >= lcs[i][j + 1] {
            i += 1;
        } else {
            j += 1;
        }
    }

    let time = |w: &Value, key: &str| w[key].as_f64().unwrap_or(0.0);
    let mut out: Vec<Value> = Vec::new();
    let mut j = 0;
    while j < next.len() {
        if let Some(i) = matched[j] {
            let mut kept = old[i].as_object().cloned().unwrap_or_else(Map::new);
            kept.insert("w".into(), json!(next[j]));
            out.push(Value::Object(kept));
            j += 1;
            continue;
        }
        // A run of new words: spread them between the neighbouring kept words.
        let mut k = j;
        while k < next.len() && matched[k].is_none() {
            k += 1;
        }
        let from = out.last().map_or(start, |w| time(w, "e"));
        let to = if k < next.len() { time(&old[matched[k].unwrap()], "s") } else { end };
        let step = (to - from).max(0.0) / (k - j) as f64;
        for (x, word) in next.iter().enumerate().take(k).skip(j) {
            let s = from + step * (x - j) as f64;
            out.push(json!({ "w": word, "s": round2(s), "e": round2(s + step) }));
        }
        j = k;
    }
    out
}

// --------------------------------------------------------------------------- //
// Transcripts as shown
// --------------------------------------------------------------------------- //

/// Underline a Listen recording's tasks: which words each task was said in
/// (its timed words, or its plain text's words without timings), and where
/// each task starts.
pub fn mark_dictation(d: &mut Dictation) {
    let timed: Vec<(&str, f64)> = d
        .words
        .as_array()
        .map(|ws| ws.iter().map(|w| (w["w"].as_str().unwrap_or(""), w["s"].as_f64().unwrap_or(0.0))).collect())
        .unwrap_or_default();
    let shown: Vec<&str> = if timed.is_empty() { d.text.split_whitespace().collect() } else { timed.iter().map(|w| w.0).collect() };
    let quotes: Vec<Option<&str>> = d.tasks.iter().map(|t| t.quote.as_deref()).collect();
    d.word_tasks = task_of_words(&shown, &quotes);
    let at: Vec<Option<f64>> = d.tasks.iter().map(|t| if timed.is_empty() { None } else { quote_start(&timed, t.quote.as_deref()) }).collect();
    for (t, at) in d.tasks.iter_mut().zip(at) {
        t.at_s = at;
    }
}

/// A meeting's transcript as shown, with its tasks marked. A task's quote can
/// run across lines, so it's matched against the whole meeting at once.
pub fn meeting_transcript(db: &Db, id: i64) -> anyhow::Result<MeetingTranscript> {
    let segments = db.transcript(id)?;
    let tasks = db.tasks(Some(id))?;
    let words: Vec<Vec<Word>> =
        segments.iter().map(|s| s.words.clone().filter(|w| !w.is_empty()).unwrap_or_else(|| spread_words(s))).collect();
    let flat: Vec<(&str, f64)> = words.iter().flatten().map(|w| (w.w.as_str(), w.s)).collect();
    let quotes: Vec<Option<&str>> = tasks.iter().map(|t| t.quote.as_deref()).collect();
    let flat_tasks = task_of_words(&flat.iter().map(|w| w.0).collect::<Vec<_>>(), &quotes);
    let marks = tasks
        .iter()
        .map(|t| TaskMark { description: t.description.clone(), quote: t.quote.clone(), at_s: quote_start(&flat, t.quote.as_deref()) })
        .collect();
    let mut at = 0;
    let segments = segments
        .into_iter()
        .zip(words)
        .map(|(s, words)| {
            let word_tasks = flat_tasks[at..at + words.len()].to_vec();
            at += words.len();
            SegmentView {
                mine: s.speaker == ME,
                renamable: s.speaker != ME,
                automatic: is_automatic_speaker(&s.speaker),
                start: s.start,
                end: s.end,
                speaker: s.speaker,
                text: s.text,
                words,
                word_tasks,
            }
        })
        .collect();
    Ok(MeetingTranscript { segments, tasks: marks })
}

/// Fix a transcript line's text; its words are re-timed from the ones it had.
pub fn edit_meeting_line(db: &Db, meeting_id: i64, index: usize, text: &str) -> anyhow::Result<()> {
    let text = text.trim();
    anyhow::ensure!(!text.is_empty(), "A line can't be empty");
    let segments = db.transcript(meeting_id)?;
    let seg = segments.get(index).ok_or_else(|| anyhow::anyhow!("That line is no longer there"))?;
    let old = seg.words.clone().filter(|w| !w.is_empty()).unwrap_or_else(|| spread_words(seg));
    let old: Vec<Value> = old.iter().map(|w| json!({ "w": w.w, "s": w.s, "e": w.e })).collect();
    let words: Vec<Word> = serde_json::from_value(Value::Array(retime_words(&old, text, seg.start, seg.end)))?;
    db.update_transcript_line(meeting_id, index, text, words)
}

/// Fix a Listen recording's text; its words are re-timed from the ones it had.
/// Returns the recording as saved.
pub fn edit_dictation(db: &Db, id: i64, text: &str) -> anyhow::Result<Dictation> {
    let text = text.trim();
    anyhow::ensure!(!text.is_empty(), "The text can't be empty");
    let d = db.dictation(id)?.ok_or_else(|| anyhow::anyhow!("Recording not found"))?;
    let old = d.words.as_array().cloned().unwrap_or_default();
    let words = retime_words(&old, text, 0.0, d.duration_ms as f64 / 1000.0);
    db.update_dictation_text(id, text, &Value::Array(words))?;
    db.dictation(id)?.ok_or_else(|| anyhow::anyhow!("Recording not found"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn w(word: &str, s: f64, e: f64) -> Value {
        json!({ "w": word, "s": s, "e": e })
    }

    #[test]
    fn compares_words_ignoring_case_and_punctuation() {
        assert_eq!(norm("Hello,"), "hello");
        assert_eq!(norm("“Don't”"), "dont");
        // Gujarati vowel signs and the virama are part of the word; the danda isn't.
        assert_eq!(norm("કર્યું।"), "કર્યું");
        assert_eq!(norm("..."), "");
    }

    #[test]
    fn edited_text_keeps_the_times_of_unchanged_words() {
        let old = vec![w("send", 0.0, 0.5), json!({ "w": "the", "s": 0.5, "e": 0.7, "st": "typed" }), w("report", 0.7, 1.2)];
        let out = retime_words(&old, "Send the final report.", 0.0, 2.0);
        let words: Vec<&str> = out.iter().map(|x| x["w"].as_str().unwrap()).collect();
        assert_eq!(words, ["Send", "the", "final", "report."]);
        assert_eq!((out[0]["s"].as_f64(), out[1]["st"].as_str()), (Some(0.0), Some("typed")));
        // The new word fills the time between its neighbours.
        assert_eq!((out[2]["s"].as_f64(), out[2]["e"].as_f64()), (Some(0.7), Some(0.7)));
        assert_eq!(out[3]["s"].as_f64(), Some(0.7));
    }

    #[test]
    fn new_words_at_the_end_share_the_rest_of_the_time() {
        let out = retime_words(&[w("hello", 0.0, 1.0)], "hello there friend", 0.0, 3.0);
        let times: Vec<(f64, f64)> = out.iter().map(|x| (x["s"].as_f64().unwrap(), x["e"].as_f64().unwrap())).collect();
        assert_eq!(times, [(0.0, 1.0), (1.0, 2.0), (2.0, 3.0)]);
    }

    #[test]
    fn old_lines_get_words_spread_by_length() {
        let seg = Segment { start: 10.0, end: 13.0, speaker: "Me".into(), text: "ab cd".into(), words: None };
        let ws = spread_words(&seg);
        assert_eq!(ws.len(), 2);
        assert_eq!((ws[0].s, ws[1].s, ws[1].e), (10.0, 11.5, 13.0));
    }

    #[test]
    fn finds_where_a_task_was_said() {
        let words = ["Okay,", "Priya:", "please", "send", "the", "report", "today."];
        let marks = task_of_words(&words, &[Some("Priya: send the report"), Some("not said")]);
        assert_eq!(marks, [None, None, None, Some(0), Some(0), Some(0), None]);
        let timed: Vec<(&str, f64)> = words.iter().enumerate().map(|(i, w)| (*w, i as f64)).collect();
        assert_eq!(quote_start(&timed, Some("send the report")), Some(3.0));
        // Reworded ending: the best match of its first words (3 or more) wins.
        assert_eq!(quote_start(&timed, Some("send the report by Friday")), Some(3.0));
        assert_eq!(quote_start(&timed, Some("send it")), None);
    }

    fn temp_db() -> Db {
        static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
        let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("voicedesk-transcript-{}-{n}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        Db::open(&dir.join("t.db")).unwrap()
    }

    fn task(description: &str, quote: &str) -> crate::db::NewTask {
        crate::db::NewTask { description: description.into(), assigned_by: None, due: None, quote: Some(quote.into()) }
    }

    #[test]
    fn a_meeting_transcript_marks_its_tasks_across_lines() {
        let db = temp_db();
        let id = db.create_meeting("Weekly", "meeting").unwrap();
        let line = |start: f64, speaker: &str, text: &str, timed: bool| {
            let mut s = Segment { start, end: start + 2.0, speaker: speaker.into(), text: text.into(), words: None };
            if timed {
                s.words = Some(spread_words(&s));
            }
            s
        };
        // The second line is from an older transcript, without word timings.
        let segments = vec![line(0.0, "Speaker 1", "Nishchay please send", true), line(2.0, "Me", "the report today", false)];
        db.save_transcript(id, &segments, 4.0).unwrap();
        db.add_task(Some(id), &task("Send the report", "Priya: send the report")).unwrap();

        let t = meeting_transcript(&db, id).unwrap();
        assert_eq!(t.tasks.len(), 1);
        let at = t.tasks[0].at_s.unwrap();
        assert!((at - t.segments[0].words[2].s).abs() < 1e-9, "starts at \"send\"");
        assert_eq!(t.segments[0].word_tasks, [None, None, Some(0)]);
        assert_eq!(t.segments[1].word_tasks, [Some(0), Some(0), None]);
        assert_eq!(t.segments[1].words.len(), 3, "an untimed line gets its words spread");
        assert!(t.segments[0].renamable && t.segments[0].automatic && !t.segments[0].mine);
        assert!(!t.segments[1].renamable && t.segments[1].mine);

        // Fixing a line keeps the words that didn't change where they were.
        let before = t.segments[0].words.clone();
        edit_meeting_line(&db, id, 0, "Nishchay, please send").unwrap();
        let after = &meeting_transcript(&db, id).unwrap().segments[0];
        assert_eq!(after.text, "Nishchay, please send");
        assert_eq!(after.words.iter().map(|w| w.s).collect::<Vec<_>>(), before.iter().map(|w| w.s).collect::<Vec<_>>());
        assert!(edit_meeting_line(&db, id, 0, "  ").is_err());
    }

    #[test]
    fn a_fixed_recording_keeps_what_happened_to_its_words() {
        let db = temp_db();
        let words = json!([{ "w": "hello", "s": 0.2, "e": 0.6, "st": "typed" }, { "w": "wold", "s": 0.6, "e": 1.0, "st": "typed" }]);
        let d = db.add_dictation("hello wold", 1500, None, &words).unwrap();
        let saved = edit_dictation(&db, d.id, "hello world").unwrap();
        assert_eq!(saved.text, "hello world");
        assert_eq!(saved.words[0], json!({ "w": "hello", "s": 0.2, "e": 0.6, "st": "typed" }));
        assert_eq!((saved.words[1]["w"].as_str(), saved.words[1]["s"].as_f64(), saved.words[1]["e"].as_f64()), (Some("world"), Some(0.6), Some(1.5)));
    }

    #[test]
    fn tells_automatic_speaker_names_apart() {
        assert!(is_automatic_speaker("Speaker 2") && is_automatic_speaker("Others"));
        assert!(!is_automatic_speaker("Priya") && !is_automatic_speaker("Speaker") && !is_automatic_speaker("Speaker two"));
    }
}
