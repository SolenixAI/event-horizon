//! The Sunshine watchdog: restarts Sunshine when it stops answering on its HTTP port
//! and no stream is live. Sunshine can wedge at startup in its screen capture, a
//! portal call that never returns, and nothing else brings it back. A live stream
//! is never touched.

use crate::linux_install::{Commands, Files, Layout, SUNSHINE_SERVICE};
use std::time::Duration;

/// Sunshine's HTTP port. It stops accepting connections when Sunshine wedges.
pub const HTTP_PORT: u16 = 47989;
/// How often the port is checked.
pub const CHECK_EVERY: Duration = Duration::from_secs(15);
/// How long Sunshine must stop answering before it is restarted.
pub const DOWN_FOR: Duration = Duration::from_secs(60);
/// The least time between two restarts, so a Sunshine that keeps failing is not
/// restarted in a loop.
pub const RESTART_GAP: Duration = Duration::from_secs(600);

/// What the watchdog does on one check.
#[derive(Debug, PartialEq, Eq)]
pub enum Step {
    /// Sunshine answers, or a stream is live: nothing to do.
    Fine,
    /// Sunshine is down, but not for long enough yet, or it was restarted too recently.
    Wait,
    /// Restart Sunshine now.
    Restart,
}

/// What the watchdog remembers between checks. `now` is any clock that only grows.
#[derive(Debug, Default)]
pub struct Watch {
    down_since: Option<Duration>,
    last_restart: Option<Duration>,
}

impl Watch {
    pub fn step(&mut self, now: Duration, answering: bool, streaming: bool) -> Step {
        if answering || streaming {
            self.down_since = None;
            return Step::Fine;
        }
        let since = *self.down_since.get_or_insert(now);
        if now.saturating_sub(since) < DOWN_FOR {
            return Step::Wait;
        }
        if self
            .last_restart
            .is_some_and(|last| now.saturating_sub(last) < RESTART_GAP)
        {
            return Step::Wait;
        }
        self.last_restart = Some(now);
        self.down_since = None;
        Step::Restart
    }
}

/// Whether a stream is live: the one-screen switch saves the outputs it turned off.
pub fn streaming(files: &dyn Files, layout: &Layout) -> bool {
    files
        .read(&layout.stream_screen_saved())
        .is_some_and(|saved| !saved.trim().is_empty())
}

/// One check. Restarts Sunshine when the watch says so, and returns what it decided.
pub fn check(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    watch: &mut Watch,
    now: Duration,
    answering: bool,
) -> Result<Step, String> {
    let step = watch.step(now, answering, streaming(files, layout));
    if step == Step::Restart {
        eprintln!(
            "sunshine watchdog: Sunshine stopped answering on port {HTTP_PORT}; restarting it"
        );
        cmd.run("systemctl", &["--user", "restart", SUNSHINE_SERVICE])?;
    }
    Ok(step)
}

/// Checks forever, every `CHECK_EVERY`. `answering` asks the port; `clock` gives the time.
pub fn run(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    answering: &dyn Fn() -> bool,
    clock: &dyn Fn() -> Duration,
) -> ! {
    let mut watch = Watch::default();
    loop {
        if let Err(e) = check(cmd, files, layout, &mut watch, clock(), answering()) {
            eprintln!("sunshine watchdog: {e}");
        }
        cmd.pause(CHECK_EVERY);
    }
}
