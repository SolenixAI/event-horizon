//! `install` on Linux: the steps are in `linux_install`. This wires in the
//! real PC: its environment, its files and its commands.

use super::{SystemCommands, SystemFiles};
use crate::linux_install::{self, Commands, Files, Layout};
use crate::virtual_screen::screen_size;
use std::collections::{HashMap, HashSet};
use std::path::Path;

/// Installs on this PC.
pub fn install(config_dir: &Path) -> Result<(), String> {
    let layout = layout(config_dir)?;
    linux_install::install(
        &SystemCommands,
        &SystemFiles,
        &layout,
        screen_size(None),
        &linux_install::random_secret,
    )
}

/// Why this PC gets no virtual screen, or None when it can have one.
pub fn screen_skip(config_dir: &Path) -> Option<String> {
    let layout = layout(config_dir).ok()?;
    linux_install::screen_skip(&SystemFiles, &layout)
}

/// Places the virtual screen beside the desk monitor. The screen's unit runs this.
pub fn place_virtual_screen() -> Result<(), String> {
    linux_install::place_virtual_screen(&SystemCommands)
}

/// Keeps the virtual screen on. The guard's unit runs this.
pub fn guard_virtual_screen(config_dir: &Path) -> Result<(), String> {
    let layout = layout(config_dir)?;
    let stream_active = || crate::sunshine_watchdog::streaming(&SystemFiles, &layout);
    let live = || crate::linux_install::virtual_screen_stream_active(&SystemFiles, &layout);
    let recover = || {
        if stream_active() {
            Ok(())
        } else {
            linux_install::stream_screen(&SystemCommands, &SystemFiles, &layout, false)
        }
    };
    crate::display_guard::run_with_recovery(&SystemCommands, &live, &recover)
}

/// The one-screen mode around a stream. Sunshine runs this as a stream starts and ends.
pub fn stream_screen(config_dir: &Path, on: bool) -> Result<(), String> {
    let layout = layout(config_dir)?;
    linux_install::stream_screen(&SystemCommands, &SystemFiles, &layout, on)
}

fn layout(config_dir: &Path) -> Result<Layout, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    Ok(Layout::from_env(config_dir, exe))
}

/// Keeps Sunshine healthy: restarts it when its port stops answering or its
/// NVIDIA Flatpak extension changes, after any live stream ends.
pub fn sunshine_watchdog(config_dir: &Path) -> Result<(), String> {
    let layout = layout(config_dir)?;
    let start = std::time::Instant::now();
    let answering = || port_answers(crate::sunshine_watchdog::HTTP_PORT);
    let stale_nvidia_extension = || stale_nvidia_flatpak_extension();
    crate::sunshine_watchdog::run(
        &SystemCommands,
        &SystemFiles,
        &layout,
        &answering,
        &stale_nvidia_extension,
        &|| start.elapsed(),
    )
}

/// Checks the sandbox process metadata for its loaded extension commits.
fn stale_nvidia_flatpak_extension() -> bool {
    let pids = SystemCommands
        .capture("pgrep", &["-x", "sunshine"])
        .unwrap_or_default();
    let expected_extension_id = SystemFiles
        .read(Path::new("/sys/module/nvidia/version"))
        .and_then(|version| crate::sunshine_watchdog::nvidia_extension_id(&version));
    pids.lines()
        .filter_map(|pid| pid.trim().parse::<u32>().ok())
        .any(|pid| {
            let metadata = Path::new("/proc")
                .join(pid.to_string())
                .join("root/.flatpak-info");
            let Some(instance_info) = SystemFiles.read(&metadata) else {
                return false;
            };
            let Some(runtime_path) = crate::sunshine_watchdog::flatpak_runtime_path(&instance_info)
            else {
                return false;
            };
            let Some(installation) =
                crate::sunshine_watchdog::flatpak_installation_option(runtime_path)
            else {
                return false;
            };
            let Some(runtime_arch) = crate::sunshine_watchdog::flatpak_runtime_arch(runtime_path)
            else {
                return false;
            };
            let Some((installed_ids, installed_commits)) =
                active_nvidia_extension_state(&SystemCommands, installation, runtime_arch)
            else {
                return false;
            };
            crate::sunshine_watchdog::has_stale_nvidia_extension_with_installed_ids(
                &instance_info,
                &installed_ids,
                &installed_commits,
                expected_extension_id.as_deref(),
            )
        })
}

/// Reads full NVIDIA extension commits from Sunshine's Flatpak installation.
/// A failed per-extension lookup is skipped; other active commits stay useful.
#[cfg(test)]
fn active_nvidia_extension_commits(
    commands: &dyn Commands,
    installation: &str,
) -> Option<HashMap<String, String>> {
    let refs = commands
        .capture(
            "flatpak",
            &[installation, "list", "--runtime", "--columns=application"],
        )
        .ok()?;
    let mut commits = HashMap::new();
    for id in refs
        .lines()
        .map(str::trim)
        .filter(|id| id.starts_with("org.freedesktop.Platform.GL.nvidia-"))
    {
        let Ok(commit) = commands.capture("flatpak", &[installation, "info", "--show-commit", id])
        else {
            continue;
        };
        commits.insert(id.to_owned(), commit.trim().to_owned());
    }
    Some(commits)
}

/// Reads commits for exact installed refs in Sunshine's architecture.
fn active_nvidia_extension_state(
    commands: &dyn Commands,
    installation: &str,
    runtime_arch: &str,
) -> Option<(HashSet<String>, HashMap<String, HashSet<String>>)> {
    let refs = commands
        .capture(
            "flatpak",
            &[installation, "list", "--runtime", "--columns=ref"],
        )
        .ok()?;
    let mut installed_ids = HashSet::new();
    let mut refs_by_id: HashMap<String, Vec<String>> = HashMap::new();
    for full_ref in refs.lines().map(str::trim) {
        let Some(id) = nvidia_extension_ref_id(full_ref, runtime_arch) else {
            continue;
        };
        installed_ids.insert(id.to_owned());
        refs_by_id
            .entry(id.to_owned())
            .or_default()
            .push(full_ref.to_owned());
    }

    let mut commits: HashMap<String, HashSet<String>> = HashMap::new();
    for (id, full_refs) in refs_by_id {
        for full_ref in full_refs {
            let Ok(commit) = commands.capture(
                "flatpak",
                &[installation, "info", "--show-commit", &full_ref],
            ) else {
                // The installed ID is still known; an unreadable commit is unknown,
                // not evidence that Sunshine must restart.
                continue;
            };
            commits
                .entry(id.clone())
                .or_default()
                .insert(commit.trim().to_owned());
        }
    }
    Some((installed_ids, commits))
}

fn nvidia_extension_ref_id<'a>(full_ref: &'a str, runtime_arch: &str) -> Option<&'a str> {
    let parts = full_ref.split('/').collect::<Vec<_>>();
    let (id, arch, branch) = match parts.as_slice() {
        [id, arch, branch] => (*id, *arch, *branch),
        ["runtime", id, arch, branch] => (*id, *arch, *branch),
        _ => return None,
    };
    // Freedesktop's proprietary NVIDIA GL extension has the fixed 1.4 branch.
    // Ignore other refs with the same ID so a stale parallel branch cannot
    // make an old loaded commit look current.
    if arch != runtime_arch || branch != "1.4" {
        return None;
    }
    if !id.starts_with("org.freedesktop.Platform.GL.nvidia-") {
        return None;
    }
    Some(id)
}

/// Whether something accepts connections on the port, on this PC.
fn port_answers(port: u16) -> bool {
    let addr = std::net::SocketAddr::from(([127, 0, 0, 1], port));
    std::net::TcpStream::connect_timeout(&addr, std::time::Duration::from_secs(3)).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    struct FlatpakCommands;

    impl Commands for FlatpakCommands {
        fn run(&self, _program: &str, _args: &[&str]) -> Result<(), String> {
            Ok(())
        }

        fn capture(&self, _program: &str, args: &[&str]) -> Result<String, String> {
            match args {
                ["--system", "list", "--runtime", "--columns=application"] => {
                    Ok(format!("{CURRENT_EXTENSION}\n{UNREADABLE_EXTENSION}\n"))
                }
                ["--system", "info", "--show-commit", CURRENT_EXTENSION] => {
                    Ok("active-commit\n".to_string())
                }
                ["--system", "info", "--show-commit", UNREADABLE_EXTENSION] => {
                    Err("extension is temporarily unavailable".to_string())
                }
                _ => Err("unexpected Flatpak command".to_string()),
            }
        }

        fn pause(&self, _how_long: Duration) {}
    }

    const CURRENT_EXTENSION: &str = "org.freedesktop.Platform.GL.nvidia-615-71-09";
    const UNREADABLE_EXTENSION: &str = "org.freedesktop.Platform.GL.nvidia-999-00-00";

    #[test]
    fn one_unreadable_extension_does_not_hide_other_active_commits() {
        let commits = active_nvidia_extension_commits(&FlatpakCommands, "--system").unwrap();

        assert_eq!(
            commits.get(CURRENT_EXTENSION).map(String::as_str),
            Some("active-commit")
        );
        assert!(!commits.contains_key(UNREADABLE_EXTENSION));
        assert!(crate::sunshine_watchdog::has_stale_nvidia_extension(
            &format!("[Instance]\nruntime-extensions={CURRENT_EXTENSION}=old-commit\n"),
            &commits,
            Some(CURRENT_EXTENSION)
        ));
    }
}
