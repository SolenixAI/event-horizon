//! Prompt on Linux: a desktop notification with Allow and Deny buttons
//! (freedesktop Notifications; Plasma shows the buttons). Closing it, or
//! letting it time out, is Deny.

use crate::ports::{Decision, Prompt};
use std::collections::HashMap;
use zbus::blocking::{Connection, Proxy};
use zbus::zvariant::Value;

#[derive(Clone, Copy, Default)]
pub struct Notification;

impl Prompt for Notification {
    async fn ask_allow(&self, mac_name: &str, code: &str) -> Decision {
        let (mac_name, code) = (mac_name.to_string(), code.to_string());
        tokio::task::spawn_blocking(move || ask(&mac_name, &code).unwrap_or(Decision::Deny))
            .await
            .unwrap_or(Decision::Deny)
    }
}

fn ask(mac_name: &str, code: &str) -> zbus::Result<Decision> {
    let connection = Connection::session()?;
    let notifications = Proxy::new(
        &connection,
        "org.freedesktop.Notifications",
        "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications",
    )?;
    let mut signals = notifications.receive_all_signals()?;
    let mut hints: HashMap<&str, Value> = HashMap::new();
    hints.insert("urgency", Value::U8(2)); // stays on screen until answered
    let id: u32 = notifications.call(
        "Notify",
        &(
            "Event Horizon",
            0u32,
            "video-display",
            format!("Allow {mac_name} to use this PC?"),
            format!("Code on your Mac: {code}"),
            vec!["allow", "Allow", "deny", "Deny"],
            hints,
            120_000i32,
        ),
    )?;
    for message in &mut signals {
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
