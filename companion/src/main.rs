//! The Event Horizon companion: run at login on the gaming PC.

// No console window on Windows: it runs in the background at login.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(any(target_os = "linux", windows))]
#[tokio::main]
async fn main() {
    use event_horizon_companion::{
        Host, discovery, games, library, link, play, sunshine::LocalSunshine,
    };
    use std::collections::HashMap;

    // `play <appid>`: what Sunshine runs to open a game.
    let args: Vec<String> = std::env::args().collect();
    if args.get(1).map(String::as_str) == Some("play") {
        let (Some(appid), Some(root)) = (args.get(2), games::steam_root()) else {
            eprintln!("usage: event-horizon-companion play <steam app id> (needs Steam installed)");
            std::process::exit(2);
        };
        play::run(&root, appid);
        return;
    }

    let dir = config_dir();

    // `install`: turn this PC into an Event Horizon host.
    #[cfg(windows)]
    if args.get(1).map(String::as_str) == Some("install") {
        let elevated_child = args.iter().any(|a| a == "--elevated");
        let result = event_horizon_companion::os::windows::install(&dir, elevated_child).await;
        // One message at the end (not on CI, where nobody can click it).
        if std::env::var_os("CI").is_none() && !elevated_child {
            let text = match &result {
                Ok(()) => "This PC is ready. Open Event Horizon on your Mac.".to_string(),
                Err(e) => format!("Setup stopped: {e}"),
            };
            event_horizon_companion::os::windows::notice(&text);
        }
        if let Err(e) = result {
            eprintln!("install: {e}");
            std::process::exit(1);
        }
        return;
    }
    let env: HashMap<String, String> = std::fs::read_to_string(dir.join("companion.env"))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| line.split_once('='))
        .map(|(k, v)| {
            (
                k.trim().to_string(),
                v.trim().trim_matches(|c| c == '"' || c == '\'').to_string(),
            )
        })
        .collect();
    let get = |key: &str| {
        env.get(key)
            .cloned()
            .or_else(|| std::env::var(key).ok())
            .unwrap_or_default()
    };
    let sunshine = LocalSunshine::new(get("SUNSHINE_USER"), get("SUNSHINE_PASSWORD"));

    #[cfg(target_os = "linux")]
    let host = Host::new(
        sunshine.clone(),
        event_horizon_companion::os::linux::Notification,
        event_horizon_companion::os::linux::SessionInhibit,
    );
    #[cfg(windows)]
    let host = Host::new(
        sunshine.clone(),
        event_horizon_companion::os::windows::Dialog,
        event_horizon_companion::os::windows::PowerRequest,
    );

    // The game shelf: the PC's Steam games, kept in Sunshine's apps.
    if let Some(steam_root) = games::steam_root() {
        let exe = std::env::current_exe()
            .map(|p| p.display().to_string())
            .unwrap_or_default();
        let sunshine_flatpak = cfg!(target_os = "linux")
            && std::path::Path::new(&get("HOME"))
                .join(".var/app/dev.lizardbyte.app.Sunshine")
                .is_dir();
        let (play, covers) = if sunshine_flatpak {
            // Flatpak Sunshine runs commands in its sandbox and reads only its own folders.
            let sunshine_config = std::path::Path::new(&get("HOME"))
                .join(".var/app/dev.lizardbyte.app.Sunshine/config/sunshine");
            (
                format!("flatpak-spawn --host setsid {exe} play"),
                sunshine_config.join("covers"),
            )
        } else {
            (format!("\"{exe}\" play"), dir.join("covers"))
        };
        let overrides = env
            .iter()
            .filter_map(|(k, v)| {
                k.strip_prefix("LAUNCH_")
                    .map(|id| (id.to_string(), v.clone()))
            })
            .collect();
        let source = games::SteamGames {
            steam_root,
            covers,
            play,
            overrides,
        };
        let sunshine = sunshine.clone();
        tokio::spawn(async move {
            loop {
                match library::sync(&sunshine, &source).await {
                    Ok(changes) if !changes.is_empty() => println!("library: {changes:?}"),
                    Ok(_) => {}
                    Err(e) => eprintln!("library: {e:?}"),
                }
                tokio::time::sleep(std::time::Duration::from_secs(600)).await;
            }
        });
    }

    let pc_name = hostname();
    let _announced = discovery::announce(&pc_name)
        .map_err(|e| eprintln!("discovery: {e}"))
        .ok();
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", discovery::PORT))
        .await
        .expect("the companion's port is free");
    println!(
        "Event Horizon companion on {pc_name}, port {}",
        discovery::PORT
    );
    link::serve(listener, host, dir.join("macs.json")).await;
}

#[cfg(any(target_os = "linux", windows))]
fn config_dir() -> std::path::PathBuf {
    #[cfg(windows)]
    let base = std::env::var_os("APPDATA")
        .map(std::path::PathBuf::from)
        .unwrap_or_default();
    #[cfg(not(windows))]
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|| {
            std::path::PathBuf::from(std::env::var_os("HOME").unwrap_or_default()).join(".config")
        });
    base.join("event-horizon")
}

#[cfg(any(target_os = "linux", windows))]
fn hostname() -> String {
    std::env::var("COMPUTERNAME")
        .ok()
        .or_else(|| std::fs::read_to_string("/etc/hostname").ok())
        .map(|name| name.trim().to_string())
        .filter(|name| !name.is_empty())
        .unwrap_or_else(|| "PC".to_string())
}

#[cfg(not(any(target_os = "linux", windows)))]
fn main() {
    eprintln!("the companion runs on Windows and Linux PCs");
}
