//! The Sunshine watchdog restarts Sunshine after a sustained failure or stale
//! NVIDIA runtime. It never restarts during a live stream.

use crate::linux_install::{Commands, Files, Layout, SUNSHINE_SERVICE};
use std::collections::{HashMap, HashSet};
use std::path::Path;
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

    /// A stale NVIDIA extension is decisive, so restart after streams end.
    /// This check bypasses the HTTP-port timeout.
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

/// Whether Sunshine uses an older NVIDIA extension than the installed runtime.
/// `/.flatpak-info` records the extension ID and commit loaded by the process.
pub fn has_stale_nvidia_extension(
    instance_info: &str,
    installed_commits: &HashMap<String, String>,
    expected_extension_id: Option<&str>,
) -> bool {
    let installed_ids = installed_commits.keys().cloned().collect();
    let installed_commits = installed_commits
        .iter()
        .map(|(id, commit)| (id.clone(), HashSet::from([commit.clone()])))
        .collect();
    has_stale_nvidia_extension_with_installed_ids(
        instance_info,
        &installed_ids,
        &installed_commits,
        expected_extension_id,
    )
}

/// Separates confirmed installed IDs from commits that Flatpak could read.
/// A listed extension with a transiently unreadable commit is not stale.
pub fn has_stale_nvidia_extension_with_installed_ids(
    instance_info: &str,
    installed_ids: &HashSet<String>,
    installed_commits: &HashMap<String, HashSet<String>>,
    expected_extension_id: Option<&str>,
) -> bool {
    let running = nvidia_extension_commits(instance_info);
    if running.is_empty() || installed_ids.is_empty() {
        return false;
    }

    if let Some(expected) = expected_extension_id.filter(|id| installed_ids.contains(*id)) {
        return running.iter().any(|(id, commit)| {
            id != expected
                || installed_commits
                    .get(expected)
                    .is_some_and(|active| !active.contains(commit))
        });
    }

    running.iter().any(|(id, commit)| {
        if !installed_ids.contains(id) {
            // Flatpak confirmed that this running NVIDIA ref was removed.
            return true;
        }
        installed_commits
            .get(id)
            .is_some_and(|active| !active.contains(commit))
    })
}

/// NVIDIA driver extension IDs and commit IDs recorded in a Flatpak instance.
pub fn nvidia_extension_commits(instance_info: &str) -> Vec<(String, String)> {
    instance_value(instance_info, "runtime-extensions=")
        .into_iter()
        .flat_map(|value| value.split(';'))
        .filter_map(|extension| {
            let (id, commit) = extension.split_once('=')?;
            id.starts_with("org.freedesktop.Platform.GL.nvidia-")
                .then(|| (id.to_string(), commit.to_string()))
        })
        .collect()
}

/// The installation path of the running Flatpak runtime.
pub fn flatpak_runtime_path(instance_info: &str) -> Option<&str> {
    instance_value(instance_info, "runtime-path=")
}

/// The architecture in the running Flatpak runtime's deployment path.
pub fn flatpak_runtime_arch(runtime_path: &str) -> Option<&str> {
    Path::new(runtime_path)
        .parent()?
        .parent()?
        .parent()?
        .file_name()?
        .to_str()
}

fn instance_value<'a>(instance_info: &'a str, key: &str) -> Option<&'a str> {
    let mut in_instance = false;
    for line in instance_info.lines() {
        let line = line.trim();
        if line.starts_with('[') && line.ends_with(']') {
            in_instance = line == "[Instance]";
            continue;
        }
        if in_instance {
            if let Some(value) = line.strip_prefix(key) {
                return Some(value);
            }
        }
    }
    None
}

/// Flatpak's CLI selector for the installation that launched the runtime.
pub fn flatpak_installation_option(runtime_path: &str) -> Option<&'static str> {
    if runtime_path.contains("/.local/share/flatpak/") {
        Some("--user")
    } else if runtime_path.starts_with("/var/lib/flatpak/") {
        Some("--system")
    } else {
        None
    }
}

/// The NVIDIA GL extension ID selected by a host driver version.
pub fn nvidia_extension_id(driver_version: &str) -> Option<String> {
    let version = driver_version.trim();
    let parts = version.split('.').collect::<Vec<_>>();
    if parts.len() < 2
        || parts.iter().any(|part| {
            part.is_empty() || !part.chars().all(|character| character.is_ascii_digit())
        })
    {
        return None;
    }
    Some(format!(
        "org.freedesktop.Platform.GL.nvidia-{}",
        parts.join("-")
    ))
}

/// Whether a stream is live: the one-screen switch saves the outputs it turned off.
pub fn streaming(files: &dyn Files, layout: &Layout) -> bool {
    crate::linux_install::stream_screen_active(files, layout)
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
