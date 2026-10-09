//! Hold this PC awake for N seconds (default 10): a manual check of the OS
//! adapter. `cargo run --example hold_awake -- 30`

#[cfg(any(target_os = "linux", windows))]
fn main() {
    use event_horizon_companion::Awake;
    let seconds: u64 = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(10);
    #[cfg(target_os = "linux")]
    let guard = event_horizon_companion::os::linux::SessionInhibit.hold();
    #[cfg(windows)]
    let guard = event_horizon_companion::os::windows::PowerRequest.hold();
    println!("holding the PC awake for {seconds} s");
    std::thread::sleep(std::time::Duration::from_secs(seconds));
    drop(guard);
    println!("released");
}

#[cfg(not(any(target_os = "linux", windows)))]
fn main() {
    println!("the companion runs on Windows and Linux PCs");
}
