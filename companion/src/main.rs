//! The Event Horizon companion: run at login on the gaming PC.

#[cfg(any(target_os = "linux", windows))]
#[tokio::main]
async fn main() {
    use event_horizon_companion::{Host, discovery, link, sunshine::LocalSunshine};
    use std::collections::HashMap;

    let dir = config_dir();
    let env: HashMap<String, String> = std::fs::read_to_string(dir.join("companion.env"))
        .unwrap_or_default()
        .lines()
        .filter_map(|line| line.split_once('='))
        .map(|(k, v)| (k.trim().to_string(), v.trim().to_string()))
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
        sunshine,
        event_horizon_companion::os::linux::Notification,
        event_horizon_companion::os::linux::SessionInhibit,
    );
    #[cfg(windows)]
    let host = Host::new(
        sunshine,
        event_horizon_companion::os::windows::Dialog,
        event_horizon_companion::os::windows::PowerRequest,
    );

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
