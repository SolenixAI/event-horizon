//! Awake on Linux: the freedesktop screensaver inhibit (no blanking, no
//! auto-lock; what KDE honours for video players) plus a logind idle and
//! sleep inhibitor, so the PC neither locks nor suspends.

use crate::ports::Awake;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::OwnedFd;

pub const WHO: &str = "Event Horizon";
pub const WHY: &str = "A Mac is connected";

#[derive(Clone, Copy, Default)]
pub struct SessionInhibit;

pub struct SessionInhibitGuard {
    screensaver: Option<(Connection, u32)>,
    _logind: Option<OwnedFd>,
}

impl Awake for SessionInhibit {
    type Guard = SessionInhibitGuard;

    fn hold(&self) -> SessionInhibitGuard {
        SessionInhibitGuard {
            screensaver: inhibit_screensaver()
                .map_err(|e| eprintln!("awake: screensaver inhibit failed: {e}"))
                .ok(),
            _logind: inhibit_logind()
                .map_err(|e| eprintln!("awake: logind inhibit failed: {e}"))
                .ok(),
        }
    }
}

fn screensaver(connection: &Connection) -> zbus::Result<Proxy<'_>> {
    Proxy::new(
        connection,
        "org.freedesktop.ScreenSaver",
        "/org/freedesktop/ScreenSaver",
        "org.freedesktop.ScreenSaver",
    )
}

fn inhibit_screensaver() -> zbus::Result<(Connection, u32)> {
    let connection = Connection::session()?;
    let cookie: u32 = screensaver(&connection)?.call("Inhibit", &(WHO, WHY))?;
    Ok((connection, cookie))
}

fn inhibit_logind() -> zbus::Result<OwnedFd> {
    let connection = Connection::system()?;
    let manager = Proxy::new(
        &connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )?;
    // The inhibitor lasts while this file descriptor stays open.
    manager.call("Inhibit", &("idle:sleep", WHO, WHY, "block"))
}

impl Drop for SessionInhibitGuard {
    fn drop(&mut self) {
        if let Some((connection, cookie)) = self.screensaver.take()
            && let Ok(proxy) = screensaver(&connection)
        {
            let _: zbus::Result<()> = proxy.call("UnInhibit", &(cookie,));
        }
    }
}
