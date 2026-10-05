//! Downloads for what Voice Desk fetches on first run (task AI, its model,
//! the speech engine's Python): resumable, checked, with progress, then unpacked.

use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use anyhow::{anyhow, Context, Result};
use sha2::{Digest, Sha256};

/// HTTP client for big downloads. No total timeout (2.5 GB on a slow line takes
/// hours); a connection that stalls for a minute fails, and the next try resumes.
pub fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(30))
        .read_timeout(Duration::from_secs(60))
        .build()
        .expect("http client")
}

/// SHA-256 of the files Voice Desk downloads, from the publishers (GitHub release
/// `digest`, Hugging Face `X-Linked-ETag`) for the pinned versions. A file not
/// listed is downloaded unchecked, so bumping a pinned version never blocks setup;
/// the tests check every current file is listed.
const SHA256: &[(&str, &str)] = &[
    // llama.cpp b11320
    ("llama-b11320-bin-win-vulkan-x64.zip", "20e11c93085112d15bad9716531954c6752024c023153c96b493349041ae5779"),
    ("llama-b11320-bin-win-cpu-x64.zip", "20661e00d6e7a98cecf87342af12d6bf836803229000cf19b338521273bd1fc1"),
    ("llama-b11320-bin-macos-arm64.tar.gz", "f6f337fc7d2ff9260f53177cf4fe6bbf6b0f7faa75a49fb224aaf66885a5c956"),
    ("llama-b11320-bin-macos-x64.tar.gz", "ca6d7198ac258466ec109ef81fd0700467758218a74a4736936876c56e7ff1d1"),
    ("llama-b11320-bin-ubuntu-arm64.tar.gz", "88589b963d8e2ffd2d4df2f542ed7e301fb636b637c99081f5d58646aee20a9a"),
    ("llama-b11320-bin-ubuntu-vulkan-x64.tar.gz", "5fb648c3fd7ea35e4a4a05b53db6a82e1f10e049c6cfc22845d7c6c3481e454b"),
    ("llama-b11320-bin-ubuntu-x64.tar.gz", "ef1856938dc1434138ce53688791eb0d2d64cf46e309a0942a12bba3366c0919"),
    // python-build-standalone 20260929, CPython 3.12.14
    (
        "cpython-3.12.14+20260929-x86_64-pc-windows-msvc-install_only_stripped.tar.gz",
        "f38e68f4d612ade6dd50c894fc80b14c0be0c3b5201145d6fff5f20b9323204d",
    ),
    (
        "cpython-3.12.14+20260929-aarch64-apple-darwin-install_only_stripped.tar.gz",
        "1bb3e53d231ee2c8881e8daf6426f4dd95bff0dda496af0f3af300357aa998d0",
    ),
    (
        "cpython-3.12.14+20260929-x86_64-apple-darwin-install_only_stripped.tar.gz",
        "62891cf4a32ed18b6b4174def999184b5186371422c52dd92d941401db0f0e41",
    ),
    (
        "cpython-3.12.14+20260929-x86_64-unknown-linux-gnu-install_only_stripped.tar.gz",
        "ef605200f8174e87ecfc308e52a88127543f85dd5c940dc5e92cab244b98a003",
    ),
    (
        "cpython-3.12.14+20260929-aarch64-unknown-linux-gnu-install_only_stripped.tar.gz",
        "706111f834ae1557314f48b7293ddc72cc96e952aa75c5d31f56c2b7ddeac3d3",
    ),
    // Task AI models (unsloth, at the commits pinned in llm.rs)
    ("Qwen3-1.7B-Q4_K_M.gguf", "b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897"),
    ("Qwen3-4B-Q4_K_M.gguf", "f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a"),
];

/// The published SHA-256 of a download, by its file name.
pub fn sha256_of(file: &str) -> Option<&'static str> {
    SHA256.iter().find(|(f, _)| *f == file).map(|(_, h)| *h)
}

fn sidecar(dest: &Path, ext: &str) -> PathBuf {
    PathBuf::from(format!("{}.{ext}", dest.display()))
}

fn hash_file(path: &Path) -> Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(h.finalize().iter().map(|b| format!("{b:02x}")).collect())
}

/// Check the finished `.part` against its digest, then move it into place.
async fn finish(part: &Path, dest: &Path, sha256: Option<&str>) -> Result<()> {
    if let Some(want) = sha256 {
        let p = part.to_path_buf();
        let got = tauri::async_runtime::spawn_blocking(move || hash_file(&p)).await??;
        if !got.eq_ignore_ascii_case(want) {
            let _ = std::fs::remove_file(part);
            let _ = std::fs::remove_file(sidecar(dest, "part.etag"));
            let name = dest.file_name().unwrap_or_default().to_string_lossy();
            return Err(anyhow!("The download of {name} was damaged (checksum mismatch) and was deleted. Please try again."));
        }
    }
    std::fs::rename(part, dest)?;
    let _ = std::fs::remove_file(sidecar(dest, "part.etag"));
    Ok(())
}

/// Download `url` to `dest`. A `.part` file is kept on failure, and the next
/// try continues where it stopped (If-Range with the first response's ETag or
/// Last-Modified, so a changed file starts over). With `sha256`, the finished
/// file must match it. `on_progress(done_bytes, total_bytes)`.
pub async fn fetch(
    http: &reqwest::Client,
    url: &str,
    dest: &Path,
    sha256: Option<&str>,
    mut on_progress: impl FnMut(u64, u64),
) -> Result<()> {
    if dest.exists() {
        return Ok(());
    }
    if let Some(dir) = dest.parent() {
        std::fs::create_dir_all(dir)?;
    }
    let part = sidecar(dest, "part");
    let validator_file = sidecar(dest, "part.etag");
    let have = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
    let validator = std::fs::read_to_string(&validator_file).ok().filter(|v| !v.trim().is_empty());
    let mut req = http.get(url);
    if have > 0 {
        req = req.header("Range", format!("bytes={have}-"));
        if let Some(v) = &validator {
            req = req.header("If-Range", v.trim());
        }
    }
    let mut resp = req.send().await.with_context(|| format!("couldn't reach {url}"))?;
    let status = resp.status();
    if status.as_u16() == 416 {
        // Nothing left to send: the .part is already complete (a stop just before
        // the rename), or it's longer than the file and must start over.
        let total = resp
            .headers()
            .get("content-range")
            .and_then(|v| v.to_str().ok())
            .and_then(|v| v.rsplit('/').next())
            .and_then(|n| n.parse::<u64>().ok());
        if total == Some(have) {
            on_progress(have, have);
            return finish(&part, dest, sha256).await;
        }
        let _ = std::fs::remove_file(&part);
        let _ = std::fs::remove_file(&validator_file);
        return Err(anyhow!("download had to restart; please try again: {url}"));
    }
    if !status.is_success() {
        return Err(anyhow!("download failed ({status}): {url}"));
    }
    // 206: the server continues the partial file; 200: it starts over.
    let resumed = status.as_u16() == 206 && have > 0;
    if !resumed {
        // Strong validators only (a weak "W/" ETag isn't allowed in If-Range).
        let headers = resp.headers();
        let etag = headers.get("etag").and_then(|v| v.to_str().ok()).filter(|e| !e.starts_with("W/"));
        let v = etag.or_else(|| headers.get("last-modified").and_then(|v| v.to_str().ok())).unwrap_or("");
        let _ = std::fs::write(&validator_file, v);
    }
    let start = if resumed { have } else { 0 };
    let total = start + resp.content_length().unwrap_or(0);
    let mut file = std::fs::OpenOptions::new().create(true).append(resumed).write(true).truncate(!resumed).open(&part)?;
    let mut done = start;
    on_progress(done, total);
    while let Some(chunk) = resp.chunk().await? {
        file.write_all(&chunk)?;
        done += chunk.len() as u64;
        on_progress(done, total);
    }
    file.flush()?;
    drop(file);
    if total > 0 && done < total {
        return Err(anyhow!("download stopped early ({done} of {total} bytes); it will continue next time"));
    }
    finish(&part, dest, sha256).await
}

/// Voice Desk's download folder (models, runtime, task AI); free space is checked on its disk.
pub fn base_dir() -> PathBuf {
    crate::system::voicedesk_models_dir().parent().map(Path::to_path_buf).unwrap_or_default()
}

/// Free bytes on the disk holding `path` (None if it can't be told).
fn free_space(path: &Path) -> Option<u64> {
    let disks = sysinfo::Disks::new_with_refreshed_list();
    let p = path.to_string_lossy().to_lowercase();
    disks
        .list()
        .iter()
        .filter(|d| p.starts_with(&d.mount_point().to_string_lossy().to_lowercase()))
        .max_by_key(|d| d.mount_point().as_os_str().len())
        .map(|d| d.available_space())
}

/// Fail early, with a clear message, when `need_gb` (+20% for unpacking and
/// pip's temporary files) won't fit on Voice Desk's disk.
pub fn ensure_free_space(need_gb: f64) -> Result<()> {
    let Some(free) = free_space(&base_dir()) else { return Ok(()) };
    let free_gb = free as f64 / 1e9;
    if need_gb > 0.0 && free_gb < need_gb * 1.2 {
        return Err(anyhow!("Not enough disk space: needs {:.1} GB, {free_gb:.1} GB free", need_gb * 1.2));
    }
    Ok(())
}

/// A folder unpacked next to its final place, then renamed into it: an
/// interrupted unpack never looks like a finished one.
pub fn staging(dir: &Path) -> PathBuf {
    let staging = PathBuf::from(format!("{}.unpacking", dir.display()));
    let _ = std::fs::remove_dir_all(&staging);
    staging
}

/// Move a finished `staging` folder into place (replacing a half-finished one).
pub fn commit(staging: &Path, dir: &Path) -> Result<()> {
    if dir.exists() {
        std::fs::remove_dir_all(dir).with_context(|| format!("couldn't replace {}", dir.display()))?;
    }
    std::fs::rename(staging, dir).with_context(|| format!("couldn't move {} into place", dir.display()))
}

/// Unpack a .zip or .tar.gz into `dir` (flattening its folders), keeping only
/// files `keep` accepts. Returns the unpacked files.
pub fn unpack(archive: &Path, dir: &Path, keep: impl Fn(&str) -> bool) -> Result<Vec<PathBuf>> {
    let name = archive.to_string_lossy().to_lowercase();
    if name.ends_with(".zip") {
        return unzip(archive, dir, keep);
    }
    std::fs::create_dir_all(dir)?;
    let mut tar = tar::Archive::new(flate2::read::GzDecoder::new(std::fs::File::open(archive)?));
    let mut out = Vec::new();
    let mut links = Vec::new();
    for entry in tar.entries()? {
        let mut entry = entry?;
        if !entry.header().entry_type().is_file() && !entry.header().entry_type().is_symlink() {
            continue;
        }
        let Some(file) = entry.path()?.file_name().map(|n| n.to_string_lossy().to_string()) else { continue };
        if !keep(&file) {
            continue;
        }
        let path = dir.join(&file);
        if entry.header().entry_type().is_symlink() {
            // libfoo.so -> libfoo.so.1: keep a copy under the link's name.
            if let Some(target) = entry.link_name()?.and_then(|t| t.file_name().map(|n| n.to_owned())) {
                out.push(path.clone());
                let _ = std::fs::remove_file(&path);
                links.push((path, dir.join(target)));
            }
            continue;
        }
        entry.unpack(&path)?;
        out.push(path);
    }
    for (link, target) in links {
        let _ = std::fs::copy(&target, &link);
    }
    Ok(out)
}

/// Unpack a .tar.gz into `dir`, keeping its folders (Python's install).
pub fn extract_tree(archive: &Path, dir: &Path) -> Result<()> {
    std::fs::create_dir_all(dir)?;
    let mut tar = tar::Archive::new(flate2::read::GzDecoder::new(std::fs::File::open(archive)?));
    tar.set_preserve_permissions(true);
    tar.unpack(dir).with_context(|| format!("couldn't unpack {}", archive.display()))
}

fn unzip(zip: &Path, dir: &Path, keep: impl Fn(&str) -> bool) -> Result<Vec<PathBuf>> {
    std::fs::create_dir_all(dir)?;
    let mut archive = zip::ZipArchive::new(std::fs::File::open(zip)?)?;
    let mut out = Vec::new();
    for i in 0..archive.len() {
        let mut f = archive.by_index(i)?;
        if f.is_dir() {
            continue;
        }
        let Some(name) = f.enclosed_name().and_then(|p| p.file_name().map(|n| n.to_string_lossy().to_string())) else {
            continue;
        };
        if !keep(&name) {
            continue;
        }
        let path = dir.join(&name);
        let mut w = std::fs::File::create(&path)?;
        std::io::copy(&mut f, &mut w)?;
        #[cfg(unix)]
        if let Some(mode) = f.unix_mode() {
            use std::os::unix::fs::PermissionsExt;
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(mode))?;
        }
        out.push(path);
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn unzips_flat_and_filtered() {
        let dir = std::env::temp_dir().join(format!("vd-unzip-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let zpath = dir.join("a.zip");
        {
            let mut z = zip::ZipWriter::new(std::fs::File::create(&zpath).unwrap());
            let opts = zip::write::SimpleFileOptions::default();
            z.start_file("build/bin/llama-server.exe", opts).unwrap();
            z.write_all(b"exe").unwrap();
            z.start_file("build/bin/README.md", opts).unwrap();
            z.write_all(b"doc").unwrap();
            z.finish().unwrap();
        }
        let out = unpack(&zpath, &dir.join("x"), |n| n.ends_with(".exe")).unwrap();
        assert_eq!(out, vec![dir.join("x").join("llama-server.exe")]);
        assert_eq!(std::fs::read(&out[0]).unwrap(), b"exe");
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn hashes_and_checks_downloads() {
        let dir = std::env::temp_dir().join(format!("vd-hash-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let (part, dest) = (dir.join("f.bin.part"), dir.join("f.bin"));
        std::fs::write(&part, b"abc").unwrap();
        assert_eq!(hash_file(&part).unwrap(), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        let rt = tokio::runtime::Builder::new_current_thread().build().unwrap();
        let bad = rt.block_on(finish(&part, &dest, Some(&"0".repeat(64))));
        assert!(bad.unwrap_err().to_string().contains("checksum") && !part.exists() && !dest.exists());
        std::fs::write(&part, b"abc").unwrap();
        rt.block_on(finish(&part, &dest, sha256_of("none"))).unwrap();
        assert!(dest.exists() && !part.exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn staged_folders_replace_half_finished_ones() {
        let dir = std::env::temp_dir().join(format!("vd-stage-{}", std::process::id())).join("llama");
        std::fs::create_dir_all(&dir).unwrap();
        std::fs::write(dir.join("half.dll"), b"x").unwrap();
        let s = staging(&dir);
        std::fs::create_dir_all(&s).unwrap();
        std::fs::write(s.join("llama-server.exe"), b"exe").unwrap();
        commit(&s, &dir).unwrap();
        assert!(dir.join("llama-server.exe").exists() && !dir.join("half.dll").exists() && !s.exists());
        let _ = std::fs::remove_dir_all(dir.parent().unwrap());
    }

    #[test]
    fn free_space_is_known_for_voice_desks_disk() {
        assert!(free_space(&base_dir()).is_some_and(|b| b > 0));
        assert!(ensure_free_space(1e6).unwrap_err().to_string().starts_with("Not enough disk space: needs"));
    }
}
