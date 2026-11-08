//! Linux implementations for the installer's process and filesystem ports.

use crate::linux_install::{Commands, Files};
use std::path::Path;
use std::time::Duration;

/// Runs programs on the PC.
pub(crate) struct SystemCommands;

impl Commands for SystemCommands {
    fn run(&self, program: &str, args: &[&str]) -> Result<(), String> {
        let status = std::process::Command::new(program)
            .args(args)
            .status()
            .map_err(|error| format!("{program}: {error}"))?;
        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "{program} {} ended with {:?}",
                args.join(" "),
                status.code()
            ))
        }
    }

    fn capture(&self, program: &str, args: &[&str]) -> Result<String, String> {
        let output = std::process::Command::new(program)
            .args(args)
            .output()
            .map_err(|error| format!("{program}: {error}"))?;
        if output.status.success() {
            Ok(String::from_utf8_lossy(&output.stdout).into_owned())
        } else {
            Err(format!(
                "{program} {} ended with {:?}",
                args.join(" "),
                output.status.code()
            ))
        }
    }

    fn pause(&self, duration: Duration) {
        std::thread::sleep(duration);
    }
}

/// Reads and writes the real filesystem.
pub(crate) struct SystemFiles;

impl Files for SystemFiles {
    fn read(&self, path: &Path) -> Option<String> {
        std::fs::read_to_string(path).ok()
    }

    fn write(&self, path: &Path, text: &str) -> Result<(), String> {
        make_parent(path)?;
        std::fs::write(path, text).map_err(|error| format!("write {}: {error}", path.display()))
    }

    fn exists(&self, path: &Path) -> bool {
        path.is_file()
    }

    fn restrict(&self, path: &Path) {
        restrict_to_owner(path);
    }

    fn copy(&self, from: &Path, to: &Path) -> Result<(), String> {
        make_parent(to)?;
        // Replace, not overwrite: a running companion keeps its old file.
        let _ = std::fs::remove_file(to);
        std::fs::copy(from, to)
            .map(|_| ())
            .map_err(|error| format!("copy the companion: {error}"))
    }
}

fn make_parent(path: &Path) -> Result<(), String> {
    match path.parent() {
        Some(directory) => std::fs::create_dir_all(directory).map_err(|error| error.to_string()),
        None => Ok(()),
    }
}

#[cfg(unix)]
fn restrict_to_owner(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}

#[cfg(not(unix))]
fn restrict_to_owner(_path: &Path) {}
