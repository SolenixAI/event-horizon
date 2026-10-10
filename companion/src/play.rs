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

/// What `play` asks of the PC: Steam, the game's process, and the clock.
/// `run` uses the real PC; tests use fakes.
pub trait GameSession {
    /// Ask Steam to open the game.
    fn open(&self);
    /// Is the game's process running right now?
    fn running(&self) -> bool;
    /// Did Steam refuse to launch the game since `since` (Steam's local time)?
    fn refused_since(&self, since: &str) -> bool;
    /// Is the game installed and up to date?
    fn up_to_date(&self) -> bool;
    /// Steam's local time, `YYYY-MM-DD HH:MM:SS`.
    fn now(&self) -> String;
    /// Wait before the next check.
    fn pause(&self, every: Duration);
}

/// Open the game, relaunch once after an update, and stay open while the
/// game runs, so Sunshine keeps it current. Gives up after 15 minutes if
/// the game never starts.
pub fn play_game(game: &impl GameSession) {
    let since = game.now();
    game.open();
    let mut relaunched = false;
    let mut started = false;
    for _ in 0..300 {
        game.pause(POLL);
        if game.running() {
            started = true;
            break;
        }
        if !relaunched && game.refused_since(&since) && game.up_to_date() {
            relaunched = true;
            game.pause(Duration::from_secs(2));
            game.open();
        }
    }
    while started && game.running() {
        game.pause(POLL);
    }
}

const POLL: Duration = Duration::from_secs(3);

/// `play <appid>` on this PC: the game's install folder is in `steam_root`.
pub fn run(steam_root: &Path, appid: &str) {
    play_game(&SteamGame { steam_root, appid });
}

/// The real PC: Steam in `steam_root`, the game `appid`.
struct SteamGame<'a> {
    steam_root: &'a Path,
    appid: &'a str,
}

impl GameSession for SteamGame<'_> {
    fn open(&self) {
        open(self.steam_root, self.appid);
    }

    fn running(&self) -> bool {
        running(self.appid)
    }

    fn refused_since(&self, since: &str) -> bool {
        let log = std::fs::read_to_string(self.steam_root.join("logs/console_log.txt"))
            .unwrap_or_default();
        refused_since(&log, self.appid, since)
    }

    fn up_to_date(&self) -> bool {
        installed(self.steam_root, self.appid)
    }

    fn now(&self) -> String {
        chrono::Local::now().format("%Y-%m-%d %H:%M:%S").to_string()
    }

    fn pause(&self, every: Duration) {
        std::thread::sleep(every);
    }
}

/// How to ask Steam to open a game on Linux: a Flatpak Steam has no
/// `steam` on the PATH, so it goes through `flatpak run`.
#[cfg_attr(windows, allow(dead_code))]
pub fn launch_command(steam_root: &Path, appid: &str) -> Vec<String> {
    let url = format!("steam://rungameid/{appid}");
    let flatpak = steam_root
        .to_string_lossy()
        .contains(".var/app/com.valvesoftware.Steam");
    let program: &[&str] = if flatpak {
        &["flatpak", "run", "com.valvesoftware.Steam"]
    } else {
        &["steam"]
    };
    program.iter().map(|s| s.to_string()).chain([url]).collect()
}

fn open(steam_root: &Path, appid: &str) {
    #[cfg(windows)]
    let result = {
        let _ = steam_root;
        std::process::Command::new("cmd")
            .args(["/c", "start", "", &format!("steam://rungameid/{appid}")])
            .status()
            .map(|_| ())
    };
    #[cfg(not(windows))]
    let result = {
        // Its own process group: Sunshine ends the app's group when play
        // exits, and must not take Steam down with it.
        use std::os::unix::process::CommandExt;
        let command = launch_command(steam_root, appid);
        std::process::Command::new(&command[0])
            .args(&command[1..])
            .process_group(0)
            .spawn()
            .map(|_| ())
    };
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
