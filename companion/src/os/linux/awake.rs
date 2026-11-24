//! Awake on Linux: the freedesktop screensaver inhibit (no blanking, no
//! auto-lock; what KDE honours for video players) plus a logind idle and
//! sleep inhibitor, so the PC neither locks nor suspends.

use crate::ports::Awake;
use zbus::{Connection, OwnedFd, Proxy};

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
        let (screensaver, logind) = run_zbus(async {
            let ss = inhibit_screensaver()
                .await
                .map_err(|e| eprintln!("awake: screensaver inhibit failed: {e}"))
                .ok();
            let lg = inhibit_logind()
                .await
                .map_err(|e| eprintln!("awake: logind inhibit failed: {e}"))
                .ok();
            (ss, lg)
        })
        .unwrap_or((None, None));
        SessionInhibitGuard {
            screensaver,
            _logind: logind,
        }
    }
}

fn run_zbus<F, T>(future: F) -> Option<T>
where
    F: std::future::Future<Output = T> + Send + 'static,
    T: Send + 'static,
{
    std::thread::spawn(move || zbus::block_on(future))
        .join()
        .ok()
}

async fn screensaver(connection: &Connection) -> zbus::Result<Proxy<'_>> {
    Proxy::new(
        connection,
        "org.freedesktop.ScreenSaver",
        "/org/freedesktop/ScreenSaver",
        "org.freedesktop.ScreenSaver",
    )
    .await
}

async fn inhibit_screensaver() -> zbus::Result<(Connection, u32)> {
    let connection = Connection::session().await?;
    let cookie: u32 = screensaver(&connection)
        .await?
        .call("Inhibit", &(WHO, WHY))
        .await?;
    Ok((connection, cookie))
}

async fn inhibit_logind() -> zbus::Result<OwnedFd> {
    let connection = Connection::system().await?;
    let manager = Proxy::new(
        &connection,
        "org.freedesktop.login1",
        "/org/freedesktop/login1",
        "org.freedesktop.login1.Manager",
    )
    .await?;
    // The inhibitor lasts while this file descriptor stays open.
    manager
        .call("Inhibit", &("idle:sleep", WHO, WHY, "block"))
        .await
}

impl Drop for SessionInhibitGuard {
    fn drop(&mut self) {
        if let Some((connection, cookie)) = self.screensaver.take() {
            let _ = run_zbus(async move {
                if let Ok(proxy) = screensaver(&connection).await {
                    let _: zbus::Result<()> = proxy.call("UnInhibit", &(cookie,)).await;
                }
            });
        }
    }
}
