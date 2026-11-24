//! Prompt on Linux: a desktop notification with Allow and Deny buttons
//! (freedesktop Notifications; Plasma shows the buttons). Closing it, or
//! letting it time out, is Deny.

use crate::host::spaced;
use crate::ports::{Decision, Prompt};
use futures_util::StreamExt;
use std::collections::HashMap;
use zbus::{Connection, Proxy, Variant};

#[derive(Clone, Copy, Default)]
pub struct Notification;

impl Prompt for Notification {
    async fn ask_allow(&self, mac_name: &str, code: &str) -> Decision {
        ask(mac_name, code).await.unwrap_or(Decision::Deny)
    }
}

async fn ask(mac_name: &str, code: &str) -> zbus::Result<Decision> {
    let connection = Connection::session().await?;
    let notifications = Proxy::new(
        &connection,
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
    )
    .await?;
    let mut signals = notifications.receive_all_signals().await?;
    let mut hints: HashMap<&str, Variant<'_>> = HashMap::new();
    hints.insert("urgency", Variant::U8(2)); // stays on screen until answered
    let id: u32 = notifications
        .call(
            "Notify",
            &(
                "Event Horizon",
                0u32,
                "video-display",
                format!("Allow {mac_name} to use this PC?"),
                format!("Check that your Mac shows {}.", spaced(code)),
                vec!["allow", "Allow", "deny", "Deny"],
                hints,
                120_000i32,
            ),
        )
        .await?;
    while let Some(message) = signals.next().await {
        let Some(member) = message.header().member().map(|m| m.to_string()) else {
            continue;
        };
        match member.as_str() {
            "ActionInvoked" => {
                let (for_id, action): (u32, String) = message.body().deserialize()?;
                if for_id == id {
                    return Ok(if action == "allow" {
                        Decision::Allow
                    } else {
                        Decision::Deny
                    });
                }
            }
            "NotificationClosed" => {
                let (for_id, _reason): (u32, u32) = message.body().deserialize()?;
                if for_id == id {
                    return Ok(Decision::Deny);
                }
            }
            _ => {}
        }
    }
    Ok(Decision::Deny)
}
