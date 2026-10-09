//! While a Mac is connected it renews a lease, and the PC stays awake.

mod common;

use common::host_on_fakes;

#[tokio::test(start_paused = true)]
async fn a_lease_keeps_the_pc_awake() {
    let (host, awake) = host_on_fakes();

    host.lease("mac-1").await;

    assert_eq!(awake.held(), 1);
}

#[tokio::test(start_paused = true)]
async fn renewing_every_30_seconds_keeps_one_hold() {
    let (host, awake) = host_on_fakes();

    for _ in 0..10 {
        host.lease("mac-1").await;
        tokio::time::sleep(std::time::Duration::from_secs(30)).await;
    }

    assert_eq!(awake.held(), 1);
    assert_eq!(awake.holds_taken(), 1);
}

#[tokio::test(start_paused = true)]
async fn ninety_seconds_without_a_renewal_lets_the_pc_sleep() {
    let (host, awake) = host_on_fakes();

    host.lease("mac-1").await;
    tokio::time::sleep(std::time::Duration::from_secs(89)).await;
    assert_eq!(awake.held(), 1, "still inside the lease");

    tokio::time::sleep(std::time::Duration::from_secs(2)).await;
    assert_eq!(awake.held(), 0, "lease ran out");
}

#[tokio::test(start_paused = true)]
async fn two_macs_share_one_hold_until_both_go_quiet() {
    let (host, awake) = host_on_fakes();

    host.lease("mac-1").await;
    tokio::time::sleep(std::time::Duration::from_secs(60)).await;
    host.lease("mac-2").await;
    assert_eq!(awake.holds_taken(), 1);

    tokio::time::sleep(std::time::Duration::from_secs(40)).await;
    assert_eq!(
        awake.held(),
        1,
        "mac-1 is quiet, mac-2 is still inside its lease"
    );

    tokio::time::sleep(std::time::Duration::from_secs(60)).await;
    assert_eq!(awake.held(), 0, "both are quiet");
}

#[tokio::test(start_paused = true)]
async fn a_mac_coming_back_after_sleep_wakes_the_pc_again() {
    let (host, awake) = host_on_fakes();

    host.lease("mac-1").await;
    tokio::time::sleep(std::time::Duration::from_secs(120)).await;
    host.lease("mac-1").await;

    assert_eq!(awake.held(), 1);
    assert_eq!(awake.holds_taken(), 2);
}
