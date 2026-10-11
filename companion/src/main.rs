//! The Event Horizon companion: run at login on the gaming PC.

// No console window on Windows: it runs in the background at login.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(any(target_os = "linux", windows))]
#[tokio::main]
async fn main() {
    use event_horizon_companion::{
        Host, discovery, games, library, link, play, setup, sunshine::LocalSunshine, tls,
    };

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

    // `place-virtual-screen` and `guard-virtual-screen`: the screen's units run these.
    #[cfg(target_os = "linux")]
    if args.get(1).map(String::as_str) == Some("place-virtual-screen") {
        if let Err(e) = event_horizon_companion::os::linux::place_virtual_screen() {
            eprintln!("virtual screen: {e}");
            std::process::exit(1);
        }
        return;
    }
    #[cfg(target_os = "linux")]
    if args.get(1).map(String::as_str) == Some("guard-virtual-screen") {
        if let Err(e) = event_horizon_companion::os::linux::guard_virtual_screen() {
            eprintln!("display guard: {e}");
            std::process::exit(1);
        }
        return;
    }

    let dir = config_dir();
    // A panic leaves a note; it is sent only on a later lease from a Mac that shares stats.
    event_horizon_companion::crash::install_panic_hook(dir.clone());

    // `stream-screen on|off`: Sunshine runs these as a stream starts and ends, and
    // `off` before it starts, so the PC has one screen only while a stream is live.
    #[cfg(target_os = "linux")]
    if args.get(1).map(String::as_str) == Some("stream-screen") {
        let on = match args.get(2).map(String::as_str) {
            Some("on") => true,
            Some("off") => false,
            _ => {
                eprintln!("usage: event-horizon-companion stream-screen on|off");
                std::process::exit(2);
            }
        };
        if let Err(e) = event_horizon_companion::os::linux::stream_screen(&dir, on) {
            eprintln!("stream screen: {e}");
            std::process::exit(1);
        }
        return;
    }

    let companion_env = std::fs::read_to_string(dir.join("companion.env")).unwrap_or_default();

    // `install`, or a run with no argument on a PC not set up yet: turn this
    // PC into an Event Horizon host.
    let installing = args.get(1).map(String::as_str) == Some("install")
        || setup::is_first_run(&args, &companion_env);
    #[cfg(target_os = "linux")]
    if installing {
        match event_horizon_companion::os::linux::install(&dir) {
            Ok(()) => {
                println!("This PC is ready. Open Event Horizon on your Mac.");
                if let Some(why) = event_horizon_companion::os::linux::screen_skip(&dir) {
                    println!("{why}");
                }
            }
            Err(e) => {
                eprintln!("Setup stopped: {e}");
                std::process::exit(1);
            }
        }
        return;
    }
    #[cfg(windows)]
    if installing {
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
    let env = setup::parse_env(&companion_env);
    let get = |key: &str| {
        env.get(key)
            .cloned()
            .or_else(|| std::env::var(key).ok())
            .unwrap_or_default()
    };
    let sunshine = LocalSunshine::new(get("SUNSHINE_USER"), get("SUNSHINE_PASSWORD"));
    let macs = dir.join("macs.json");

    // `--list-macs` and `--unpair <mac id>`: the Macs this PC trusts, from the
    // PC itself. They work whether or not the companion is running.
    match args.get(1).map(String::as_str) {
        Some("--list-macs") => {
            for (mac_id, mac_name) in link::list(&macs) {
                println!("{mac_id}  {mac_name}");
            }
            return;
        }
        Some("--unpair") => {
            let Some(mac_id) = args.get(2) else {
                eprintln!("usage: event-horizon-companion --unpair <mac id>");
                std::process::exit(2);
            };
            match link::unpair_mac(&sunshine, &macs, mac_id).await {
                Ok(true) => println!("This Mac is no longer paired."),
                Ok(false) => println!("No paired Mac has that id."),
                Err(e) => {
                    eprintln!("Sunshine did not forget it, so nothing changed: {e:?}");
                    std::process::exit(1);
                }
            }
            return;
        }
        _ => {}
    }

    let identity = match tls::load_or_create(&dir) {
        Ok(identity) => identity,
        Err(e) => {
            eprintln!("the companion's certificate: {e}");
            std::process::exit(1);
        }
    };

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
            // `--wait`: flatpak-spawn returns when play does, which is when Sunshine ends the app.
            let sunshine_config = std::path::Path::new(&get("HOME"))
                .join(".var/app/dev.lizardbyte.app.Sunshine/config/sunshine");
            (
                format!("flatpak-spawn --host setsid --wait {exe} play"),
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
            library::keep_in_step(&sunshine, &source, |outcome| match outcome {
                Ok(changes) if !changes.is_empty() => println!("library: {changes:?}"),
                Ok(_) => {}
                Err(e) => eprintln!("library: {e:?}"),
            })
            .await;
        });
    }

    let pc_name = hostname();
    let _announced = discovery::announce(&pc_name, &identity.fingerprint)
        .map_err(|e| eprintln!("discovery: {e}"))
        .ok();
    let listener = tokio::net::TcpListener::bind(("0.0.0.0", discovery::PORT))
        .await
        .expect("the companion's port is free");
    println!(
        "Event Horizon companion on {pc_name}, port {}",
        discovery::PORT
    );
    link::serve(listener, identity.acceptor, host, macs).await;
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
