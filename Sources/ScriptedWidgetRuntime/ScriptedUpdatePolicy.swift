import Foundation

/// When the host next calls `update()` and `render()`. Scripts have no timers. A widget that
/// defines `update()` is updated, then rendered, on the same schedule `render()` asks for
/// with `refresh`; one that doesn't is only rendered. Changing settings runs an update (when
/// there is one) immediately. Changing only how the tile is drawn, such as moving the dock to
/// a side edge, renders again from the cached update result.
public enum ScriptedUpdatePolicy {
    public enum Step: Equatable, Sendable {
        /// Call `update()`, cache what it returns, then `render()`.
        case updateThenRender
        /// Call `render()` with the cached update result.
        case render
        /// Nothing is due. Wait this long, then decide again.
        case wait(TimeInterval)
        /// Nothing is scheduled until something changes.
        case idle
    }

    public struct Input: Equatable, Sendable {
        /// The script defines `update`.
        public var hasUpdateHook: Bool
        /// A render has completed for the current package.
        public var hasRendered: Bool
        /// The tile's settings differ from the ones last rendered.
        public var settingsChanged: Bool
        /// Compact layout changed and the settings didn't.
        public var appearanceChanged: Bool
        public var lastRender: Date?
        /// The refresh the last tile asked for, already clamped. Nil means it asked for none.
        public var refresh: TimeInterval?
        public var now: Date
        /// False while the dock is hidden; nothing runs.
        public var visible: Bool

        public init(
            hasUpdateHook: Bool, hasRendered: Bool, settingsChanged: Bool, appearanceChanged: Bool,
            lastRender: Date?, refresh: TimeInterval?, now: Date, visible: Bool
        ) {
            self.hasUpdateHook = hasUpdateHook
            self.hasRendered = hasRendered
            self.settingsChanged = settingsChanged
            self.appearanceChanged = appearanceChanged
            self.lastRender = lastRender
            self.refresh = refresh
            self.now = now
            self.visible = visible
        }
    }

    public static func step(_ input: Input) -> Step {
        guard input.visible else { return .idle }
        if !input.hasRendered || input.settingsChanged {
            return input.hasUpdateHook ? .updateThenRender : .render
        }
        if input.appearanceChanged { return .render }
        guard let refresh = input.refresh, let lastRender = input.lastRender else { return .idle }
        let remaining = refresh - input.now.timeIntervalSince(lastRender)
        if remaining <= 0 { return input.hasUpdateHook ? .updateThenRender : .render }
        return .wait(remaining)
    }
}
