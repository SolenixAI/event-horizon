# Fork Glimmer and build only the experience

Event Horizon is a fork of Glimmer, a native Swift client for Sunshine, and
Solenix builds only the experience on top: Home, grow, the cursor and
shortcut rules, the PC companion. We did not write our own stream engine or
wrap moonlight-qt, because Glimmer already streams with native macOS
frameworks at the latency we want, and the product's value is the
experience, not the transport. The cost is GPLv3 for the whole app, so the
source is public and the Mac App Store is out; we sell the signed, updated
build instead.
