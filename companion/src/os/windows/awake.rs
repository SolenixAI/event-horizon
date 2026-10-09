//! Awake on Windows: a power request, the way video players keep the
//! display on. Handle-based, so any thread may release it, and Windows
//! lists it under `powercfg /requests` with our reason.

use crate::ports::Awake;
use windows_sys::Win32::Foundation::{CloseHandle, HANDLE, INVALID_HANDLE_VALUE};
use windows_sys::Win32::System::Power::{
    PowerClearRequest, PowerCreateRequest, PowerRequestDisplayRequired, PowerRequestSystemRequired,
    PowerSetRequest,
};
use windows_sys::Win32::System::Threading::{
    POWER_REQUEST_CONTEXT_SIMPLE_STRING, REASON_CONTEXT, REASON_CONTEXT_0,
};

pub const REASON: &str = "Event Horizon: a Mac is connected";

#[derive(Clone, Copy, Default)]
pub struct PowerRequest;

pub struct PowerRequestGuard {
    handle: Option<HANDLE>,
    _reason: Vec<u16>,
}

// The handle is a kernel object; Windows allows any thread to clear it.
unsafe impl Send for PowerRequestGuard {}

impl Awake for PowerRequest {
    type Guard = PowerRequestGuard;

    fn hold(&self) -> PowerRequestGuard {
        let mut reason: Vec<u16> = REASON.encode_utf16().chain(std::iter::once(0)).collect();
        let context = REASON_CONTEXT {
            Version: 0,
            Flags: POWER_REQUEST_CONTEXT_SIMPLE_STRING,
            Reason: REASON_CONTEXT_0 {
                SimpleReasonString: reason.as_mut_ptr(),
            },
        };
        // SAFETY: `context` and `reason` outlive the call; the handle is
        // owned by the guard and closed exactly once in Drop.
        let handle = unsafe { PowerCreateRequest(&context) };
        if handle.is_null() || handle == INVALID_HANDLE_VALUE {
            eprintln!("awake: PowerCreateRequest failed");
            return PowerRequestGuard {
                handle: None,
                _reason: reason,
            };
        }
        unsafe {
            PowerSetRequest(handle, PowerRequestDisplayRequired);
            PowerSetRequest(handle, PowerRequestSystemRequired);
        }
        PowerRequestGuard {
            handle: Some(handle),
            _reason: reason,
        }
    }
}

impl Drop for PowerRequestGuard {
    fn drop(&mut self) {
        if let Some(handle) = self.handle.take() {
            // SAFETY: the handle came from PowerCreateRequest and is closed once.
            unsafe {
                PowerClearRequest(handle, PowerRequestDisplayRequired);
                PowerClearRequest(handle, PowerRequestSystemRequired);
                CloseHandle(handle);
            }
        }
    }
}
