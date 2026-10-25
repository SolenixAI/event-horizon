//! The Sunshine watchdog: restarts Sunshine when its HTTP port stays down or its
//! NVIDIA Flatpak extension has changed since the running sandbox started. A live
//! stream is never touched.

use crate::linux_install::{Commands, Files, Layout, SUNSHINE_SERVICE};
use std::collections::HashMap;
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

    /// A Sunshine process can keep its HTTP API alive while still using an
    /// old NVIDIA Flatpak extension after an update. That state is
    /// conclusive, so restart as soon as no stream is live rather than waiting
    /// for the HTTP-port timeout.
    pub fn step_with_stale_nvidia_extension(
        &mut self,
        now: Duration,
        answering: bool,
        streaming: bool,
        stale_nvidia_extension: bool,
    ) -> Step {
        if streaming {
            self.down_since = None;
            return Step::Fine;
        }
        if stale_nvidia_extension {
            self.down_since = None;
            if self
                .last_restart
                .is_some_and(|last| now.saturating_sub(last) < RESTART_GAP)
            {
                return Step::Wait;
            }
            self.last_restart = Some(now);
            return Step::Restart;
        }
        self.step(now, answering, false)
    }
}

/// Whether Sunshine's running Flatpak instance has an older NVIDIA driver
/// extension than the one currently installed. `/.flatpak-info` is the
/// effective metadata for a running Flatpak instance; its `runtime-extensions`
/// values include exact commit IDs.
pub fn has_stale_nvidia_extension(
    instance_info: &str,
    installed_commits: &HashMap<String, String>,
) -> bool {
    nvidia_extension_commits(instance_info)
        .iter()
        .any(|(id, running)| {
            installed_commits
                .get(id)
                .is_some_and(|active| active != running)
        })
}

/// NVIDIA driver extension IDs and commit IDs recorded in a Flatpak instance.
pub fn nvidia_extension_commits(instance_info: &str) -> Vec<(String, String)> {
    let mut in_instance = false;
    for line in instance_info.lines() {
        let line = line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            in_instance = line == "[Instance]";
            continue;
        }
        if !in_instance {
            continue;
        }
        let Some(value) = line.strip_prefix("runtime-extensions=") else {
            continue;
        };
        return value
            .split(';')
            .filter_map(|extension| {
                let (id, commit) = extension.split_once('=')?;
                id.starts_with("org.freedesktop.Platform.GL.nvidia-")
                    .then(|| (id.to_string(), commit.to_string()))
            })
            .collect();
    }
    Vec::new()
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
    check_with_stale_extension(cmd, files, layout, watch, now, answering, false)
}

fn check_with_stale_extension(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    watch: &mut Watch,
    now: Duration,
    answering: bool,
    stale_nvidia_extension: bool,
) -> Result<Step, String> {
    let step = watch.step_with_stale_nvidia_extension(
        now,
        answering,
        streaming(files, layout),
        stale_nvidia_extension,
    );
    if step == Step::Restart {
        if stale_nvidia_extension {
            eprintln!(
                "sunshine watchdog: Sunshine has a stale NVIDIA Flatpak extension; restarting it"
            );
        } else {
            eprintln!(
                "sunshine watchdog: Sunshine stopped answering on port {HTTP_PORT}; restarting it"
            );
        }
        cmd.run("systemctl", &["--user", "restart", SUNSHINE_SERVICE])?;
    }
    Ok(step)
}

/// Checks forever, every `CHECK_EVERY`. `answering` asks the port, and
/// `stale_nvidia_extension` compares Sunshine's loaded extension with Flatpak's
/// active deployment. `clock` gives the time.
pub fn run(
    cmd: &dyn Commands,
    files: &dyn Files,
    layout: &Layout,
    answering: &dyn Fn() -> bool,
    stale_nvidia_extension: &dyn Fn() -> bool,
    clock: &dyn Fn() -> Duration,
) -> ! {
    let mut watch = Watch::default();
    loop {
        if let Err(e) = check_with_stale_extension(
            cmd,
            files,
            layout,
            &mut watch,
            clock(),
            answering(),
            stale_nvidia_extension(),
        ) {
            eprintln!("sunshine watchdog: {e}");
        }
        cmd.pause(CHECK_EVERY);
    }
}
