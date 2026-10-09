# One Rust program for the PC companion, with OS seams

The PC companion is one Rust program for Windows and Linux: a deep core
(pairing, lease, library sync) behind a small interface, with one adapter per
OS for installing, keeping awake, prompting and finding games. Rust gives one
self-contained file per OS with no runtime to install, which is what a friend
downloading from one link needs, and one core means a fix lands on both OSes.
The Mac app stays Swift; the two meet only over the companion's three
requests on the local network.
