import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock weather tile: a condition symbol, the temperature, and the place or conditions.
struct WeatherTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @Environment(\.widgetsMayRequestAccess) private var mayRequestAccess
    @State private var service = WeatherService.shared

    private var settings: WeatherSettings { WeatherSettings(instance: instance) }

    /// Text beside the symbol on the bottom edge, under it (centered) on a side edge.
    private var textAlignment: HorizontalAlignment { edge.isVertical ? .center : .leading }

    /// Everything that should restart the refresh loop when it changes.
    private struct RefreshKey: Equatable {
        var location: WeatherLocation
        var isVisible: Bool
        var mayPrompt: Bool
    }

    var body: some View {
        let feed = service.feed(for: settings.location)
        WidgetTile {
            // Symbol then text along the bottom edge; symbol above text on a side edge.
            WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
                WeatherSymbol(name: symbolName(for: feed), size: iconSize * 0.46)
                VStack(alignment: textAlignment, spacing: 0) {
                    WidgetPrimaryText(temperatureText(for: feed))
                    WidgetSecondaryText(captionText(for: feed))
                }
                .frame(
                    maxWidth: edge.isVertical ? nil : CGFloat(iconSize * 2.2),
                    alignment: Alignment(horizontal: textAlignment, vertical: .center))
            }
        }
        .task(id: RefreshKey(location: settings.location, isVisible: isVisible, mayPrompt: mayRequestAccess)) {
            // Polling stops with the dock hidden; the loop picks up where it left off on reveal.
            guard isVisible else { return }
            await feed.autoRefresh(mayPrompt: mayRequestAccess)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: feed))
    }

    // MARK: Content

    private func symbolName(for feed: WeatherFeed) -> String {
        if let report = feed.report { return report.current.symbolName }
        switch feed.error {
        case .locationNotDetermined, .locationDenied, .locationUnavailable: return "location.slash"
        case .offline: return "wifi.slash"
        case .server: return "cloud.fill"
        case nil: return "cloud.fill"
        }
    }

    private func temperatureText(for feed: WeatherFeed) -> String {
        guard let report = feed.report else { return "—°" }
        return settings.unit.format(celsius: report.current.temperatureCelsius)
    }

    /// The place or conditions, or what's wrong when there's nothing (fresh) to show.
    private func captionText(for feed: WeatherFeed) -> String {
        guard let report = feed.report else {
            if let error = feed.error { return error.shortDescription }
            return feed.location == .current ? "Locating…" : "Loading…"
        }
        if let error = feed.error, feed.isStale(at: Date()) {
            return error.shortDescription
        }
        switch settings.caption {
        case .location: return report.place.name.isEmpty ? WeatherWidget.displayName : report.place.name
        case .condition: return report.current.condition.description
        }
    }

    private func accessibilityLabel(for feed: WeatherFeed) -> String {
        guard let report = feed.report else {
            return "Weather: \(feed.error?.shortDescription ?? "loading")"
        }
        let temperature = settings.unit.format(celsius: report.current.temperatureCelsius)
        var parts = ["Weather: \(temperature)", report.current.condition.description]
        if !report.place.name.isEmpty { parts.append(report.place.name) }
        if let error = feed.error, feed.isStale(at: Date()) { parts.append(error.shortDescription) }
        return parts.joined(separator: ", ")
    }
}

/// A weather SF Symbol in its multicolor form (yellow sun, blue rain, ...), sized in points.
struct WeatherSymbol: View {
    let name: String
    let size: Double

    var body: some View {
        Image(systemName: name)
            .symbolRenderingMode(.multicolor)
            .font(.system(size: size, weight: .medium))
            .frame(width: size * 1.25, height: size * 1.25)
            .accessibilityHidden(true)
    }
}
