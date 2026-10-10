//! Discovery: the companion's record carries the version and the fingerprint of
//! the certificate the Link serves, so a Mac can pin it.

use event_horizon_companion::discovery;

#[test]
fn the_record_carries_the_version_and_the_fingerprint() {
    let record = discovery::properties("ab12");

    assert!(record.contains(&("v", "1".to_string())));
    assert!(record.contains(&("fp", "ab12".to_string())));
}
