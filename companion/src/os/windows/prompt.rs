//! Prompt on Windows: a native Yes/No dialog in front of everything.

use crate::ports::{Decision, Prompt};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    IDYES, MB_ICONQUESTION, MB_SETFOREGROUND, MB_TOPMOST, MB_YESNO, MessageBoxW,
};

#[derive(Clone, Copy, Default)]
pub struct Dialog;

fn wide(text: &str) -> Vec<u16> {
    text.encode_utf16().chain(std::iter::once(0)).collect()
}

impl Prompt for Dialog {
    async fn ask_allow(&self, mac_name: &str, code: &str) -> Decision {
        let text = wide(&format!(
            "Allow {mac_name} to use this PC?\n\nCode on your Mac: {code}"
        ));
        let title = wide("Event Horizon");
        tokio::task::spawn_blocking(move || {
            // SAFETY: both strings are NUL-terminated and outlive the call.
            let answer = unsafe {
                MessageBoxW(
                    std::ptr::null_mut(),
                    text.as_ptr(),
                    title.as_ptr(),
                    MB_YESNO | MB_ICONQUESTION | MB_TOPMOST | MB_SETFOREGROUND,
                )
            };
            if answer == IDYES {
                Decision::Allow
            } else {
                Decision::Deny
            }
        })
        .await
        .unwrap_or(Decision::Deny)
    }
}
