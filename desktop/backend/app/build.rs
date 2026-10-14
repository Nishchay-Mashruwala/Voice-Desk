fn main() {
    vc_runtime();
    tauri_build::build()
}

/// llama.cpp's Windows builds (the task AI) import MSVCP140, VCRUNTIME140 and
/// VCRUNTIME140_1, which a fresh Windows lacks and the llama.cpp zip doesn't
/// include. Microsoft allows shipping these redistributable DLLs app-locally, so
/// they're bundled (tauri.windows.conf.json) and copied beside llama-server
/// (llm.rs). Taken from this PC's System32: GitHub's Windows runners and any PC
/// with Visual Studio have them. (Voice Desk itself doesn't need them: Rust links
/// the VC runtime statically and the UCRT is part of Windows 10/11.)
fn vc_runtime() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }
    let redist = std::path::PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap()).join("redist");
    let system32 = std::path::PathBuf::from(std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into())).join("System32");
    std::fs::create_dir_all(&redist).expect("redist folder");
    // Copied at build time, never committed.
    let _ = std::fs::write(redist.join(".gitignore"), "*\n");
    for dll in ["msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll"] {
        let to = redist.join(dll);
        if !to.exists() {
            std::fs::copy(system32.join(dll), &to).unwrap_or_else(|e| {
                panic!("{dll} not found in {} ({e}); install the Visual C++ Redistributable (x64)", system32.display())
            });
        }
    }
}
