//! `install` on Windows: one run turns this PC into an Event Horizon host.
//! Sunshine (pinned release, checked by SHA-256, silent MSI), the
//! companion's own Sunshine login, the companion in the user's apps folder,
//! started at login, and a firewall rule for it. Safe to run again.

use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Command;

const SUNSHINE_MSI: &str = "https://github.com/LizardByte/Sunshine/releases/download/v2026.914.233613/Sunshine-Windows-AMD64-installer.msi";
const SUNSHINE_MSI_SHA256: &str =
    "1d7fed8beecd5889dc7ff14cf9f42d6d38f37c3066c13c6c2a5f4e91847e0ccf";
const SUNSHINE_USER: &str = "eventhorizon";

fn sunshine_dir() -> PathBuf {
    PathBuf::from(std::env::var_os("ProgramFiles").unwrap_or_else(|| r"C:\Program Files".into()))
        .join("Sunshine")
}

fn run(program: &str, args: &[&str]) -> Result<(), String> {
    let status = Command::new(program)
        .args(args)
        .status()
        .map_err(|e| format!("{program}: {e}"))?;
    match status.code() {
        Some(0) | Some(3010) => Ok(()), // 3010: done, a restart would finish it
        code => Err(format!("{program} {} ended with {code:?}", args.join(" "))),
    }
}

fn is_admin() -> bool {
    Command::new("net")
        .arg("session")
        .output()
        .is_ok_and(|o| o.status.success())
}

/// Install everything. Asks Windows for admin once if it does not have it;
/// the companion itself always starts as the person, never elevated.
pub async fn install(config_dir: &Path, elevated_child: bool) -> Result<(), String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    if !is_admin() {
        // One UAC prompt; the elevated copy installs, then we start the companion.
        // WaitForExit waits for that copy only (Start-Process -Wait would also
        // wait for every process it starts).
        let script = format!(
            "$p = Start-Process -Verb RunAs -PassThru -FilePath '{}' -ArgumentList 'install','--elevated'; $p.WaitForExit(); exit $p.ExitCode",
            exe.display()
        );
        run("powershell", &["-NoProfile", "-Command", &script])?;
        return start(&installed_path()?);
    }

    let sunshine = sunshine_dir().join("sunshine.exe");
    if !sunshine.exists() {
        let msi = std::env::temp_dir().join("Sunshine-Windows-AMD64-installer.msi");
        let bytes = reqwest::get(SUNSHINE_MSI)
            .await
            .and_then(|r| r.error_for_status())
            .map_err(|e| format!("download Sunshine: {e}"))?
            .bytes()
            .await
            .map_err(|e| format!("download Sunshine: {e}"))?;
        let digest: String = Sha256::digest(&bytes)
            .iter()
            .map(|b| format!("{b:02x}"))
            .collect();
        if digest != SUNSHINE_MSI_SHA256 {
            return Err(format!(
                "the Sunshine download does not match its pinned SHA-256 ({digest})"
            ));
        }
        std::fs::write(&msi, &bytes).map_err(|e| e.to_string())?;
        let log = std::env::temp_dir().join("sunshine-install.log");
        run(
            "msiexec",
            &[
                "/i",
                &msi.display().to_string(),
                "/qn",
                "/norestart",
                "/l*v",
                &log.display().to_string(),
            ],
        )?;
    }

    // The companion's own login to Sunshine's local API.
    let mut bytes = [0u8; 18];
    getrandom::fill(&mut bytes).map_err(|e| e.to_string())?;
    let password: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    run(
        &sunshine.display().to_string(),
        &["--creds", SUNSHINE_USER, &password],
    )?;
    let _ = run("net", &["stop", "SunshineService"]);
    run("net", &["start", "SunshineService"])?;

    std::fs::create_dir_all(config_dir).map_err(|e| e.to_string())?;
    std::fs::write(
        config_dir.join("companion.env"),
        format!("SUNSHINE_USER={SUNSHINE_USER}\nSUNSHINE_PASSWORD={password}\n"),
    )
    .map_err(|e| e.to_string())?;

    // The companion lives in the user's apps folder and starts at login.
    let installed = installed_path()?;
    std::fs::create_dir_all(installed.parent().expect("a folder")).map_err(|e| e.to_string())?;
    if installed != exe {
        let _ = run(
            "taskkill",
            &[
                "/f",
                "/im",
                "event-horizon-companion.exe",
                "/fi",
                &format!("PID ne {}", std::process::id()),
            ],
        );
        std::fs::copy(&exe, &installed).map_err(|e| format!("copy the companion: {e}"))?;
    }
    let target = installed.display().to_string();
    run(
        "reg",
        &[
            "add",
            r"HKCU\Software\Microsoft\Windows\CurrentVersion\Run",
            "/v",
            "Event Horizon",
            "/t",
            "REG_SZ",
            "/d",
            &format!("\"{target}\""),
            "/f",
        ],
    )?;
    let _ = run(
        "netsh",
        &[
            "advfirewall",
            "firewall",
            "delete",
            "rule",
            "name=Event Horizon companion",
        ],
    );
    run(
        "netsh",
        &[
            "advfirewall",
            "firewall",
            "add",
            "rule",
            "name=Event Horizon companion",
            "dir=in",
            "action=allow",
            &format!("program={target}"),
            "enable=yes",
        ],
    )?;

    // Run by an admin directly (no UAC hop): start it now. The elevated
    // child leaves that to its unelevated parent.
    if elevated_child {
        Ok(())
    } else {
        start(&installed)
    }
}

fn installed_path() -> Result<PathBuf, String> {
    let local = std::env::var_os("LOCALAPPDATA").ok_or("LOCALAPPDATA is not set")?;
    Ok(PathBuf::from(local)
        .join("Event Horizon")
        .join("event-horizon-companion.exe"))
}

/// Start the companion detached, so this installer can exit.
fn start(installed: &Path) -> Result<(), String> {
    use std::os::windows::process::CommandExt;
    const DETACHED_PROCESS: u32 = 0x0000_0008;
    Command::new(installed)
        .creation_flags(DETACHED_PROCESS)
        .spawn()
        .map(|_| ())
        .map_err(|e| format!("start the companion: {e}"))
}
