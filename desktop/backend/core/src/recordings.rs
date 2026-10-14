//! Recordings on disk: a .wav while recording, a .flac once processed.

use std::path::{Path, PathBuf};

/// A recording saved as `path` (.wav while recording), or its compressed
/// .flac once processed. None if neither exists (deleted or expired).
pub fn recorded(path: &Path) -> Option<PathBuf> {
    let flac = path.with_extension("flac");
    [path.to_path_buf(), flac].into_iter().find(|p| p.exists())
}

/// Delete a recording in whichever format it's in.
pub fn remove_recording(path: &Path) {
    let _ = std::fs::remove_file(path.with_extension("wav"));
    let _ = std::fs::remove_file(path.with_extension("flac"));
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_a_recording_in_either_format() {
        let dir = std::env::temp_dir().join(format!("vd-rec-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let wav = dir.join("meeting-1-mic.wav");
        assert_eq!(recorded(&wav), None);
        std::fs::write(dir.join("meeting-1-mic.flac"), b"fLaC").unwrap();
        assert_eq!(recorded(&wav), Some(dir.join("meeting-1-mic.flac")));
        std::fs::write(&wav, b"RIFF").unwrap(); // still being recorded: the WAV wins
        assert_eq!(recorded(&wav), Some(wav.clone()));
        remove_recording(&wav);
        assert_eq!(recorded(&wav), None);
        let _ = std::fs::remove_dir_all(&dir);
    }
}
