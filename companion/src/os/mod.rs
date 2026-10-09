//! OS adapters for the Host's seams. One module per OS; each fills the same
//! ports, so the core never knows which PC it runs on.

#[cfg(target_os = "linux")]
pub mod linux;
#[cfg(windows)]
pub mod windows;
