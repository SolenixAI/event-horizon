//! Complete one pairing a Mac started with this PC's Sunshine: a manual
//! end-to-end check of the Sunshine adapter. Reads SUNSHINE_USER and
//! SUNSHINE_PASSWORD. `cargo run --example pair_once -- "Mac name" 1234`

use event_horizon_companion::SunshineApi;
use event_horizon_companion::sunshine::LocalSunshine;

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let mut args = std::env::args().skip(1);
    let (Some(name), Some(pin)) = (args.next(), args.next()) else {
        eprintln!("usage: pair_once <mac name> <pin>");
        std::process::exit(2);
    };
    let env = |key: &str| std::env::var(key).unwrap_or_else(|_| panic!("{key} is set"));
    let sunshine = LocalSunshine::new(env("SUNSHINE_USER"), env("SUNSHINE_PASSWORD"));
    match sunshine.submit_pin(&name, &pin).await {
        Ok(()) => println!("paired {name}"),
        Err(e) => {
            eprintln!("not paired: {e:?}");
            std::process::exit(1);
        }
    }
}
