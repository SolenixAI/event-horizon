//! The pairing window: for `WINDOW` after the companion is installed, the first
//! Mac that asks is allowed without a click at the PC, so a PC with its monitor
//! off can be set up, the way AirPods pair while their case is open. The window
//! lets one Mac in, then closes; after that, the PC asks as before.

use crate::ports::{Decision, Prompt};
use std::path::{Path, PathBuf};
use std::time::Duration;

/// How long the window stays open after install.
pub const WINDOW: Duration = Duration::from_secs(600);

/// The file that holds the window's closing time, in Unix seconds.
const FILE: &str = "pair-window-until";

/// Opens the window in `dir` at `now` (Unix seconds). The installer calls this.
pub fn open(dir: &Path, now: u64) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    std::fs::write(dir.join(FILE), (now + WINDOW.as_secs()).to_string())
}

pub struct PairWindow<P> {
    inner: P,
    path: PathBuf,
    now: Box<dyn Fn() -> u64 + Send + Sync>,
}

impl<P: Prompt> PairWindow<P> {
    /// The PC's prompt, behind the window kept in `dir`. `now` is Unix seconds.
    pub fn new(inner: P, dir: &Path, now: impl Fn() -> u64 + Send + Sync + 'static) -> Self {
        Self {
            inner,
            path: dir.join(FILE),
            now: Box::new(now),
        }
    }

    /// True once, while the window is open; the window closes as it is used.
    fn take(&self) -> bool {
        let Ok(text) = std::fs::read_to_string(&self.path) else {
            return false;
        };
        // Used or expired, the window is gone either way.
        let _ = std::fs::remove_file(&self.path);
        text.trim()
            .parse::<u64>()
            .is_ok_and(|until| (self.now)() <= until)
    }
}

impl<P: Prompt> Prompt for PairWindow<P> {
    async fn ask_allow(&self, mac_name: &str, code: &str) -> Decision {
        if self.take() {
            return Decision::Allow;
        }
        self.inner.ask_allow(mac_name, code).await
    }
}
