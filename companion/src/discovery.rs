//! Discovery: the companion announces itself on the home network as
//! `_eventhorizon._tcp`, beside Sunshine's own `_nvstream._tcp`, so the Mac
//! finds both on the same PC.

use mdns_sd::{ServiceDaemon, ServiceInfo};

pub const SERVICE: &str = "_eventhorizon._tcp.local.";
/// The companion's TCP port (Sunshine uses 47984-48010).
pub const PORT: u16 = 47970;

/// Announce this PC until the returned daemon is dropped.
pub fn announce(pc_name: &str) -> Result<ServiceDaemon, mdns_sd::Error> {
    let daemon = ServiceDaemon::new()?;
    let host = format!("{}.local.", pc_name.to_lowercase().replace(' ', "-"));
    let info =
        ServiceInfo::new(SERVICE, pc_name, &host, "", PORT, &[("v", "1")][..])?.enable_addr_auto();
    daemon.register(info)?;
    Ok(daemon)
}
