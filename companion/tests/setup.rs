//! Whether a PC is set up yet: `companion.env` holds the Sunshine login that
//! `install` writes. A run with no argument on a PC that is not set up installs.

use event_horizon_companion::setup::{is_first_run, is_set_up, parse_env};

fn args(list: &[&str]) -> Vec<String> {
    list.iter().map(|s| s.to_string()).collect()
}

const SET_UP: &str = "SUNSHINE_USER=eventhorizon\nSUNSHINE_PASSWORD=0a1b2c\n";

#[test]
fn a_run_with_no_argument_on_a_pc_not_set_up_installs() {
    assert!(is_first_run(&args(&["event-horizon-companion"]), ""));
}

#[test]
fn a_run_with_no_argument_on_a_set_up_pc_runs_the_service() {
    assert!(!is_first_run(&args(&["event-horizon-companion"]), SET_UP));
}

#[test]
fn a_run_with_an_argument_is_never_a_first_run() {
    let list_macs = args(&["event-horizon-companion", "--list-macs"]);
    assert!(!is_first_run(&list_macs, ""));
}

#[test]
fn a_blank_password_is_not_a_login() {
    assert!(!is_set_up(
        "SUNSHINE_USER=eventhorizon\nSUNSHINE_PASSWORD=\n"
    ));
    assert!(!is_set_up("SUNSHINE_PASSWORD=0a1b2c\n"));
}

#[test]
fn quotes_come_off_the_values_and_the_login_still_counts() {
    let env = parse_env("SUNSHINE_USER=\"eventhorizon\"\nSUNSHINE_PASSWORD='0a1b2c'\nLAUNCH_1=x\n");
    assert_eq!(env["SUNSHINE_PASSWORD"], "0a1b2c");
    assert_eq!(env["LAUNCH_1"], "x");
    assert!(is_set_up(
        "SUNSHINE_USER=\"eventhorizon\"\nSUNSHINE_PASSWORD='0a1b2c'\n"
    ));
}
