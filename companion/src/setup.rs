//! Whether this PC is set up: `companion.env` holds the Sunshine login that
//! `install` writes. The companion reads that file on every start.

use std::collections::HashMap;

/// The `KEY=value` pairs of a `companion.env` file. Quotes come off the values.
pub fn parse_env(text: &str) -> HashMap<String, String> {
    text.lines()
        .filter_map(|line| line.split_once('='))
        .map(|(k, v)| {
            (
                k.trim().to_string(),
                v.trim().trim_matches(|c| c == '"' || c == '\'').to_string(),
            )
        })
        .collect()
}

/// True when `companion.env` holds a Sunshine user and password.
pub fn is_set_up(companion_env: &str) -> bool {
    let env = parse_env(companion_env);
    let present = |key: &str| env.get(key).is_some_and(|v| !v.is_empty());
    present("SUNSHINE_USER") && present("SUNSHINE_PASSWORD")
}

/// A run with no argument, on a PC that is not set up yet. `args` includes
/// the program name, as `std::env::args` does.
pub fn is_first_run(args: &[String], companion_env: &str) -> bool {
    args.len() <= 1 && !is_set_up(companion_env)
}
