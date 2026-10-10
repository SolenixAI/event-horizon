#if canImport(Sparkle)
/// The update rules Event Horizon owns. Sparkle keeps the daily schedule and the
/// build-number ordering. Nothing appears over a live stream: an update window waits
/// until the stream ends, and a check the person starts waits too.
enum UpdatePolicy {
    static func mayShowWindow(isStreaming: Bool) -> Bool { !isStreaming }

    static func mayCheckNow(isStreaming: Bool) -> Bool { !isStreaming }
}
#endif
