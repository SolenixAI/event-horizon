//! `play <appid>`: what Sunshine runs to open a Steam game. Steam refuses a
//! game that needs an update, then updates it; this waits for that and
//! opens the game again, once. The cross-platform form of the tower's
//! `steam-play` script.

use std::path::Path;
use std::time::Duration;

/// Did Steam refuse to launch `appid` at or after `since` (Steam's own
/// `YYYY-MM-DD HH:MM:SS` local time, as its console log writes it)?
pub fn refused_since(console_log: &str, appid: &str, since: &str) -> bool {
    let needle = format!("AppID {appid},");
    console_log.lines().any(|line| {
        line.get(1..20).is_some_and(|stamp| stamp >= since)
            && line.contains(&needle)
            && line.contains("LaunchApp failed")
    })
}

/// Is the game installed and up to date (Steam's StateFlags 4)?
fn installed(steam_root: &Path, appid: &str) -> bool {
    std::fs::read_to_string(steam_root.join(format!("steamapps/appmanifest_{appid}.acf")))
        .map(|text| {
            text.lines()
                .any(|l| l.contains("\"StateFlags\"") && l.trim_end().ends_with("\"4\""))
        })
        .unwrap_or(false)
}

/// Open the game and stay until it runs, relaunching once after an update.
/// Gives up after 15 minutes.
pub fn run(steam_root: &Path, appid: &str) {
    let since = chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string();
    open(appid);
    let mut relaunched = false;
    for _ in 0..300 {
        std::thread::sleep(Duration::from_secs(3));
        if running(appid) {
            return;
        }
        let log =
            std::fs::read_to_string(steam_root.join("logs/console_log.txt")).unwrap_or_default();
        if !relaunched && refused_since(&log, appid, &since) && installed(steam_root, appid) {
            relaunched = true;
            std::thread::sleep(Duration::from_secs(2));
            open(appid);
        }
    }
}

fn open(appid: &str) {
    let url = format!("steam://rungameid/{appid}");
    #[cfg(windows)]
    let result = std::process::Command::new("cmd")
        .args(["/c", "start", "", &url])
        .status();
    #[cfg(not(windows))]
    let result = std::process::Command::new("steam")
        .arg(&url)
        .spawn()
        .map(|_| ());
    if let Err(e) = result {
        eprintln!("play: could not ask Steam to open {appid}: {e}");
    }
}

/// Steam starts every game through a reaper process with `AppId=<id>`.
#[cfg(target_os = "linux")]
fn running(appid: &str) -> bool {
    let needle = format!("AppId={appid}");
    std::fs::read_dir("/proc")
        .into_iter()
        .flatten()
        .flatten()
        .any(|entry| {
            std::fs::read(entry.path().join("cmdline")).is_ok_and(|cmdline| {
                cmdline
                    .split(|b| *b == 0)
                    .any(|arg| arg == needle.as_bytes())
            })
        })
}

/// Steam marks a running game in HKCU\Software\Valve\Steam\Apps\<id>\Running.
#[cfg(windows)]
fn running(appid: &str) -> bool {
    use windows_sys::Win32::System::Registry::{HKEY_CURRENT_USER, RRF_RT_REG_DWORD, RegGetValueW};
    let wide = |s: &str| {
        s.encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<u16>>()
    };
    let key = wide(&format!("Software\\Valve\\Steam\\Apps\\{appid}"));
    let value = wide("Running");
    let mut data: u32 = 0;
    let mut size = std::mem::size_of::<u32>() as u32;
    // SAFETY: every pointer is valid for the call; size matches the buffer.
    let status = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            key.as_ptr(),
            value.as_ptr(),
            RRF_RT_REG_DWORD,
            std::ptr::null_mut(),
            (&mut data as *mut u32).cast(),
            &mut size,
        )
    };
    status == 0 && data == 1
}

#[cfg(not(any(target_os = "linux", windows)))]
fn running(_appid: &str) -> bool {
    false
}
