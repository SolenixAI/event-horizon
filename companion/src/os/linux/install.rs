//! `install` on Linux: one run turns this PC into an Event Horizon host.
//! Sunshine from Flathub (with its one-time device setup, the single step
//! that asks for a password), the companion's own Sunshine login, and the
//! companion as a user service that starts with the desktop session. Safe
//! to run again.

use std::path::{Path, PathBuf};
use std::process::Command;

const SUNSHINE_APP: &str = "dev.lizardbyte.app.Sunshine";
const SUNSHINE_SERVICE: &str = "app-dev.lizardbyte.app.Sunshine.service";
const SUNSHINE_USER: &str = "eventhorizon";
const SERVICE: &str = "event-horizon-companion.service";

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|e| format!("{program}: {e}"))?;
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

fn home() -> PathBuf {
    PathBuf::from(std::env::var_os("HOME").unwrap_or_default())
}

fn sunshine_installed() -> bool {
    Command::new("flatpak")
        .args(["info", SUNSHINE_APP])
        .output()
        .is_ok_and(|o| o.status.success())
}

/// Sunshine's udev rules are in place once its device setup has run.
fn devices_ready() -> bool {
    Path::new("/etc/udev/rules.d/60-sunshine.rules").exists()
}

pub fn install(config_dir: &Path) -> Result<(), String> {
    if !sunshine_installed() {
        run(
            "flatpak",
            &[
                "remote-add",
                "--user",
                "--if-not-exists",
                "flathub",
                "https://dl.flathub.org/repo/flathub.flatpakrepo",
            ],
        )?;
        run(
            "flatpak",
            &["install", "-y", "--user", "flathub", SUNSHINE_APP],
        )?;
    }
    if !devices_ready() {
        // Sunshine's own setup: user unit + uinput/uhid rules (asks once via pkexec).
        run(
            "flatpak",
            &["run", "--command=additional-install.sh", SUNSHINE_APP],
        )?;
    }

    // The companion's own login to Sunshine's local API.
    let mut bytes = [0u8; 18];
    getrandom::fill(&mut bytes).map_err(|e| e.to_string())?;
    let password: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    run(
        "flatpak",
        &["run", SUNSHINE_APP, "--creds", SUNSHINE_USER, &password],
    )?;
    std::fs::create_dir_all(config_dir).map_err(|e| e.to_string())?;
    let env_file = config_dir.join("companion.env");
    // Keep per-game launch overrides from an earlier install.
    let kept: String = std::fs::read_to_string(&env_file)
        .unwrap_or_default()
        .lines()
        .filter(|l| !l.starts_with("SUNSHINE_USER=") && !l.starts_with("SUNSHINE_PASSWORD="))
        .map(|l| format!("{l}\n"))
        .collect();
    std::fs::write(
        &env_file,
        format!("SUNSHINE_USER={SUNSHINE_USER}\nSUNSHINE_PASSWORD={password}\n{kept}"),
    )
    .map_err(|e| e.to_string())?;
    restrict(&env_file);
    run("systemctl", &["--user", "enable", SUNSHINE_SERVICE])?;
    run("systemctl", &["--user", "restart", SUNSHINE_SERVICE])?;

    // The companion: ~/.local/bin, started with the desktop session.
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let installed = home().join(".local/bin/event-horizon-companion");
    std::fs::create_dir_all(installed.parent().expect("a folder")).map_err(|e| e.to_string())?;
    if exe.canonicalize().ok() != installed.canonicalize().ok() {
        // Replace, not overwrite: a running companion keeps its old file.
        let _ = std::fs::remove_file(&installed);
        std::fs::copy(&exe, &installed).map_err(|e| format!("copy the companion: {e}"))?;
    }
    let units = home().join(".config/systemd/user");
    std::fs::create_dir_all(&units).map_err(|e| e.to_string())?;
    std::fs::write(
        units.join(SERVICE),
        "[Unit]\nDescription=Event Horizon companion: this PC as a Mac app\nPartOf=graphical-session.target\nAfter=graphical-session.target\n\n[Service]\nExecStart=%h/.local/bin/event-horizon-companion\nRestart=on-failure\n\n[Install]\nWantedBy=graphical-session.target\n",
    )
    .map_err(|e| e.to_string())?;
    run("systemctl", &["--user", "daemon-reload"])?;
    run("systemctl", &["--user", "enable", SERVICE])?;
    run("systemctl", &["--user", "restart", SERVICE])
}

fn restrict(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600));
}
