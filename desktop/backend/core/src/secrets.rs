//! The Hugging Face token lives in the system's credential store (Windows
//! Credential Manager, macOS Keychain, Linux Secret Service), not in the
//! database file. Where no store is available it stays in the database.

use std::sync::Mutex;

#[cfg_attr(test, allow(dead_code))]
const SERVICE: &str = "com.rajvee.voicedesk";
#[cfg_attr(test, allow(dead_code))]
const ACCOUNT: &str = "huggingface-token";

/// Read once, then kept in memory (settings are read every few seconds).
static CACHE: Mutex<Option<String>> = Mutex::new(None);

#[cfg(not(test))]
fn entry() -> keyring::Result<keyring::Entry> {
    keyring::Entry::new(SERVICE, ACCOUNT)
}

#[cfg(not(test))]
fn load() -> String {
    entry().and_then(|e| e.get_password()).unwrap_or_default()
}

/// Tests never touch the real credential store.
#[cfg(test)]
fn load() -> String {
    String::new()
}

/// The stored token ("" if none).
pub fn hf_token() -> String {
    let mut c = CACHE.lock().unwrap();
    c.get_or_insert_with(load).clone()
}

/// Store (or with "", remove) the token. Returns false if the credential store
/// isn't available, so the caller keeps it in the database instead.
pub fn set_hf_token(token: &str) -> bool {
    let mut c = CACHE.lock().unwrap();
    if c.as_deref() == Some(token) {
        return true;
    }
    #[cfg(not(test))]
    {
        let stored = entry().and_then(|e| if token.is_empty() { e.delete_credential() } else { e.set_password(token) });
        match stored {
            Ok(()) | Err(keyring::Error::NoEntry) => {}
            Err(e) => {
                eprintln!("[secrets] credential store unavailable, keeping the token in the database: {e}");
                return false;
            }
        }
    }
    *c = Some(token.to_string());
    true
}

#[cfg(test)]
mod tests {
    /// The real credential store works (a throwaway entry; your token is never touched):
    /// `cargo test credential_store_live -- --ignored`
    #[test]
    #[ignore]
    fn credential_store_live() {
        let e = keyring::Entry::new("com.rajvee.voicedesk.test", "probe").unwrap();
        e.set_password("hf_test_123").unwrap();
        assert_eq!(e.get_password().unwrap(), "hf_test_123");
        e.delete_credential().unwrap();
        assert!(matches!(e.get_password(), Err(keyring::Error::NoEntry)));
    }
}
