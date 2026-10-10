# The PC companion drives an unmodified Sunshine

On the PC, Sunshine does the streaming and the PC companion only installs it
and drives it through Sunshine's own installer and local API (pairing PINs,
the apps list). We did not patch Sunshine, bundle a fork of it, or write our
own host, so every Sunshine update and fix reaches our users unchanged and
the Mac app keeps working with any current Sunshine. The cost is living
within that API: for example, Sunshine accepts a Mac only when exactly one
pairing record matches it, so we must never pair the same Mac twice.
