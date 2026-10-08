import DockCore
import Foundation

/// What a Now Playing source reports to the monitor.
public enum NowPlayingProviderEvent: Sendable {
    /// The current item, or `nil` when nothing is playing or paused.
    case track(NowPlayingTrack?)
    /// The source stopped working for good (for example, its helper can't run on this
    /// system). The monitor moves on to the next provider.
    case failed(String)
}

/// A way of finding out what's playing and controlling it. `NowPlayingMonitor` tries its
/// providers in order and uses the first one that is available, falling back when one
/// fails. Kept as a protocol so the monitor can be tested with a fake.
@MainActor
public protocol NowPlayingProvider: AnyObject {
    /// Short description for Settings, e.g. "the system's Now Playing".
    var sourceName: String { get }

    /// Starts reporting. The provider may call `handler` any number of times until ``stop()``.
    func start(handler: @escaping @MainActor (NowPlayingProviderEvent) -> Void)

    /// Stops reporting and releases any helper processes.
    func stop()

    /// Sends a transport command to the current player.
    func send(_ command: NowPlayingCommand)

    /// Lets providers that poll slow down while the dock is hidden.
    func setDockVisible(_ visible: Bool)
}
