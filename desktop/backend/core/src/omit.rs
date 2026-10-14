//! Words and phrases the user never wants in a transcript (Settings → "Leave
//! out": "umm, uh, the the"). Removed from everything Voice Desk writes down:
//! text typed at the cursor, Listen history, meeting transcripts. Applied after
//! voice commands were recognised, so leaving out a word never breaks one.
//!
//! An entry matches whole words, ignoring case and the punctuation around them
//! ("Umm," matches "umm"); a phrase matches those words in a row. A repeated
//! word ("the the") is a stutter: it becomes one "the". The text and its word timings lose the same words,
//! so playback highlighting stays in step.

use serde_json::Value;

use crate::db::{Segment, Word};

/// The parsed "Leave out" setting.
pub struct Omit {
    /// Each entry as normalised words, longest first (so "the the" wins over "the").
    phrases: Vec<Vec<String>>,
}

/// A word as it's compared: lowercase, without the punctuation around it.
fn norm(word: &str) -> String {
    word.trim_matches(|c: char| !c.is_alphanumeric() && c != '\'').to_lowercase()
}

/// Ends a sentence ("ready." "ready?" "ready!").
fn ends_sentence(word: &str) -> bool {
    word.trim_end_matches(['"', '\'', ')']).ends_with(['.', '?', '!', '…'])
}

impl Omit {
    /// From the setting: entries separated by commas or new lines.
    pub fn new(setting: &str) -> Self {
        let mut phrases: Vec<Vec<String>> = setting
            .split([',', '\n'])
            .map(|entry| entry.split_whitespace().map(norm).filter(|w| !w.is_empty()).collect::<Vec<_>>())
            .filter(|p| !p.is_empty())
            .collect();
        phrases.sort_by_key(|p| std::cmp::Reverse(p.len()));
        phrases.dedup();
        Self { phrases }
    }

    pub fn is_empty(&self) -> bool {
        self.phrases.is_empty()
    }

    /// For each word: keep it (true) or leave it out. A repeated word ("the
    /// the") is a stutter: one stays, however many times it was said.
    fn keep(&self, words: &[String]) -> Vec<bool> {
        let mut keep = vec![true; words.len()];
        let mut i = 0;
        while i < words.len() {
            let Some(p) = self.phrases.iter().find(|p| words.len() - i >= p.len() && words[i..i + p.len()] == p[..]) else {
                i += 1;
                continue;
            };
            let stutter = p.len() > 1 && p.iter().all(|w| *w == p[0]);
            let mut end = i + p.len();
            if stutter {
                while end < words.len() && words[end] == p[0] {
                    end += 1;
                }
                i += 1; // the first one stays
            }
            keep[i..end].iter_mut().for_each(|k| *k = false);
            i = end;
        }
        keep
    }

    /// Leave the matching items out; `text` gives each item's word (None: kept
    /// as is). A sentence that ended on a removed word still ends ("ready, umm."
    /// → "ready."), and one that started on it starts with a capital ("Umm, the
    /// report" → "The report").
    fn apply<T>(&self, mut items: Vec<T>, text: impl Fn(&mut T) -> Option<&mut String>) -> Vec<T> {
        if self.is_empty() || items.is_empty() {
            return items;
        }
        let words: Vec<String> = items.iter_mut().map(|it| text(it).map(|s| s.clone()).unwrap_or_default()).collect();
        let keep = self.keep(&words.iter().map(|w| norm(w)).collect::<Vec<_>>());
        let mut out: Vec<T> = Vec::with_capacity(items.len());
        // While leaving words out: the sentence end among them ("umm."), and
        // whether a sentence started on one of them ("Uh, next").
        let mut mark: Option<String> = None;
        let mut capitalize = false;
        let end_with = |out: &mut Vec<T>, mark: &str| {
            if let Some(prev) = out.last_mut().and_then(&text) {
                if !ends_sentence(prev) {
                    let bare = prev.trim_end_matches(|c: char| !c.is_alphanumeric() && !['\'', '"', ')'].contains(&c)).len();
                    prev.truncate(bare);
                    prev.push_str(mark);
                }
            }
        };
        for (i, mut item) in items.into_iter().enumerate() {
            let starts_sentence = i == 0 || ends_sentence(&words[i - 1]);
            if !keep[i] {
                if starts_sentence && words[i].chars().next().is_some_and(char::is_uppercase) {
                    capitalize = true;
                }
                if ends_sentence(&words[i]) {
                    let w = words[i].trim_end_matches(['"', '\'', ')']);
                    mark = Some(w[w.trim_end_matches(['.', '?', '!', '…']).len()..].to_string());
                    capitalize = false;
                }
                continue;
            }
            if let Some(m) = mark.take() {
                end_with(&mut out, &m);
            }
            if std::mem::take(&mut capitalize) {
                if let Some(s) = text(&mut item) {
                    let mut c = s.chars();
                    if let Some(first) = c.next().filter(|f| f.is_lowercase()) {
                        *s = first.to_uppercase().chain(c).collect();
                    }
                }
            }
            out.push(item);
        }
        if let Some(m) = mark {
            end_with(&mut out, &m);
        }
        out
    }

    /// Text with the words left out (words are separated by spaces again).
    pub fn text(&self, text: &str) -> String {
        if self.is_empty() {
            return text.to_string();
        }
        let words: Vec<String> = text.split_whitespace().map(String::from).collect();
        self.apply(words, |w| Some(w)).join(" ")
    }

    /// Timed words ({"w","s","e",...} from the engine) with the same words left out.
    pub fn json_words(&self, words: Vec<Value>) -> Vec<Value> {
        self.apply(words, |w| match w.get_mut("w") {
            Some(Value::String(s)) => Some(s),
            _ => None,
        })
    }

    pub fn words(&self, words: Vec<Word>) -> Vec<Word> {
        self.apply(words, |w| Some(&mut w.w))
    }

    /// A transcript with the words left out; lines left empty are dropped.
    pub fn segments(&self, segments: Vec<Segment>) -> Vec<Segment> {
        if self.is_empty() {
            return segments;
        }
        segments
            .into_iter()
            .map(|mut s| {
                s.text = self.text(&s.text);
                s.words = s.words.map(|w| self.words(w));
                s
            })
            .filter(|s| !s.text.trim().is_empty())
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn leaves_out_words_and_phrases() {
        let o = Omit::new("umm, uh,  The The \n");
        assert_eq!(o.text("so umm I think uh we should"), "so I think we should");
        // Case and the punctuation around a word don't matter.
        assert_eq!(o.text("Send it, UMM, today"), "Send it, today");
        // A repeated word is a stutter: one stays (however many were said).
        assert_eq!(o.text("check the the report and the numbers"), "check the report and the numbers");
        assert_eq!(o.text("The the the plan"), "The plan");
        // Other phrases go as a whole, and only those words in a row.
        let o2 = Omit::new("you know");
        assert_eq!(o2.text("it's, you know, fine and I know you"), "it's, fine and I know you");
        // Only whole words: "umbrella", "uhh" and "thumm" stay.
        assert_eq!(o.text("umbrella uhh thumm"), "umbrella uhh thumm");
        assert_eq!(o.text("umm uh"), "");
        assert!(Omit::new(" , \n").is_empty());
        assert_eq!(Omit::new("").text("umm  hello"), "umm  hello", "nothing to leave out: untouched");
    }

    #[test]
    fn sentences_keep_their_end_and_capital() {
        let o = Omit::new("umm, uh");
        assert_eq!(o.text("Umm, the report is ready."), "The report is ready.");
        assert_eq!(o.text("It's done, umm. Uh, next one?"), "It's done. Next one?");
        assert_eq!(o.text("Is it ready, umm?"), "Is it ready?");
        // Mid-sentence: no capital added.
        assert_eq!(o.text("we umm should go"), "we should go");
        // A removed lowercase filler doesn't capitalise what follows.
        assert_eq!(o.text("umm we should"), "we should");
    }

    #[test]
    fn timed_words_lose_the_same_words() {
        let o = Omit::new("umm, the the");
        let words = vec![
            json!({"w": "Umm,", "s": 0.0, "e": 0.3, "st": "typed"}),
            json!({"w": "check", "s": 0.4, "e": 0.6}),
            json!({"w": "the", "s": 0.7, "e": 0.8}),
            json!({"w": "the", "s": 0.9, "e": 1.0}),
            json!({"w": "report.", "s": 1.1, "e": 1.5}),
        ];
        let kept = o.json_words(words);
        let w: Vec<&str> = kept.iter().map(|w| w["w"].as_str().unwrap()).collect();
        assert_eq!(w, ["Check", "the", "report."]);
        assert_eq!(kept[0]["s"], 0.4);
        assert_eq!(kept[1]["s"], 0.7, "the first of the repeated words stays");
        assert_eq!(kept[0]["st"], json!(null), "other fields are kept as they were");
        assert_eq!(o.text("Umm, check the the report."), w.join(" "), "text and words agree");
    }

    #[test]
    fn transcripts_drop_lines_left_empty() {
        let o = Omit::new("umm");
        let seg = |text: &str| Segment { start: 0.0, end: 1.0, speaker: "Me".into(), text: text.into(), words: None };
        let out = o.segments(vec![seg("Umm."), seg("Let's start umm now")]);
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].text, "Let's start now");
        let timed = Segment {
            words: Some(vec![Word { w: "umm".into(), s: 0.0, e: 0.2 }, Word { w: "yes".into(), s: 0.3, e: 0.5 }]),
            ..seg("umm yes")
        };
        let out = o.segments(vec![timed]);
        assert_eq!((out[0].text.as_str(), out[0].words.as_ref().unwrap().len()), ("yes", 1));
    }
}
