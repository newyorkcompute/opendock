import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The in-dock stocks tile: one symbol's price, change and day line, the symbols in turn,
/// or a short list of changes, per the `style` setting.
struct StocksTileView: View {
    let instance: WidgetInstance

    @Environment(\.dockIconSize) private var iconSize
    @Environment(\.dockEdge) private var edge
    @Environment(\.dockIsVisible) private var isVisible
    @State private var service = StocksService.shared

    /// How long the cycle style shows each symbol.
    static let cyclePeriod: TimeInterval = 6
    /// Rows the list style fits in a tile.
    static let listRows = 3

    private var settings: StocksSettings { StocksSettings(instance: instance) }

    /// Everything that should restart the refresh loop when it changes.
    private struct RefreshKey: Equatable {
        var symbols: [String]
        var interval: Duration
        var isVisible: Bool
    }

    var body: some View {
        let symbols = settings.symbols
        WidgetTile(minWidth: edge.isVertical ? nil : minWidth(for: symbols)) {
            content(symbols)
        }
        .task(id: RefreshKey(symbols: symbols, interval: settings.refreshInterval, isVisible: isVisible)) {
            // Polling stops with the dock hidden; the loop picks up where it left off on reveal.
            guard isVisible, !symbols.isEmpty else { return }
            await service.autoRefresh(symbols, every: settings.refreshInterval)
        }
        .help(helpText(for: symbols))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: symbols))
    }

    /// Wide enough for a price like "$1,234.56" so the tile doesn't jitter as digits change.
    private func minWidth(for symbols: [String]) -> Double {
        switch settings.style {
        case .single, .cycle:
            return iconSize * (settings.showsChart ? 2.9 : 2.4)
        case .list:
            return iconSize * (symbols.count == 1 ? 2.0 : 2.3)
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ symbols: [String]) -> some View {
        if symbols.isEmpty {
            placeholder
        } else {
            switch settings.style {
            case .single:
                quote(for: symbols[0])
            case .cycle:
                if symbols.count > 1, isVisible {
                    TimelineView(.periodic(from: .now, by: Self.cyclePeriod)) { context in
                        let index = Self.cycleIndex(at: context.date, count: symbols.count)
                        ZStack {
                            quote(for: symbols[index])
                                .id(index)
                                .transition(.opacity)
                        }
                        .animation(.easeInOut(duration: 0.3), value: index)
                    }
                } else {
                    quote(for: symbols[0])
                }
            case .list:
                list(symbols)
            }
        }
    }

    /// Which symbol the cycle style shows at `date`.
    static func cycleIndex(at date: Date, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(date.timeIntervalSinceReferenceDate / cyclePeriod) % count
    }

    private var placeholder: some View {
        WidgetStack(spacing: iconSize * (edge.isVertical ? 0.06 : 0.14)) {
            Image(systemName: StocksWidget.systemImage)
                .font(.system(size: iconSize * 0.4, weight: .medium))
                .foregroundStyle(.secondary)
            WidgetSecondaryText("No symbols")
        }
    }

    // MARK: One symbol

    @ViewBuilder
    private func quote(for symbol: String) -> some View {
        let feed = service.feed(for: symbol)
        let chart = settings.showsChart ? feed.chart(for: .oneDay) : nil
        if edge.isVertical {
            VStack(spacing: 0) {
                WidgetSecondaryText(symbol)
                WidgetPrimaryText(priceText(for: feed))
                changeLabel(for: feed, size: WidgetMetrics.secondaryFontSize(for: iconSize))
                if settings.showsChart {
                    StockChartView(chart: chart, session: feed.quote?.regularSession)
                        .frame(width: iconSize * 0.8, height: iconSize * 0.36)
                        .padding(.top, iconSize * 0.04)
                }
            }
        } else {
            HStack(spacing: iconSize * 0.16) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetSecondaryText(symbol)
                    WidgetPrimaryText(priceText(for: feed))
                }
                if settings.showsChart {
                    VStack(alignment: .trailing, spacing: iconSize * 0.02) {
                        StockChartView(chart: chart, session: feed.quote?.regularSession)
                            .frame(width: iconSize * 1.1, height: iconSize * 0.4)
                        changeLabel(for: feed, size: WidgetMetrics.secondaryFontSize(for: iconSize))
                    }
                } else {
                    changeLabel(for: feed, size: WidgetMetrics.secondaryFontSize(for: iconSize) * 1.2)
                }
            }
        }
    }

    private func changeLabel(for feed: StockFeed, size: Double) -> some View {
        Text(changeText(for: feed))
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(changeColor(for: feed))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // MARK: List

    private func list(_ symbols: [String]) -> some View {
        let shown = Array(symbols.prefix(Self.listRows))
        let size = rowFontSize(rows: shown.count)
        return VStack(alignment: edge.isVertical ? .center : .leading, spacing: iconSize * 0.02) {
            ForEach(shown, id: \.self) { symbol in
                let feed = service.feed(for: symbol)
                if edge.isVertical {
                    VStack(spacing: 0) {
                        Text(symbol)
                            .font(.system(size: size * 0.85, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        changeLabel(for: feed, size: size)
                    }
                } else {
                    HStack(spacing: iconSize * 0.12) {
                        Text(symbol)
                            .font(.system(size: size, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 0)
                        changeLabel(for: feed, size: size)
                    }
                }
            }
        }
    }

    /// Text that fits `rows` rows in a tile an icon tall.
    private func rowFontSize(rows: Int) -> Double {
        let factor: Double =
            switch rows {
            case 1: 0.3
            case 2: 0.25
            default: 0.2
            }
        return max(9, iconSize * factor)
    }

    // MARK: Text

    private func priceText(for feed: StockFeed) -> String {
        guard let quote = feed.quote else { return "—" }
        return StockFormatting.price(quote.price, currency: quote.currency, fractionDigits: quote.fractionDigits)
    }

    /// The day's move, or what's wrong when there's nothing (fresh) to show.
    private func changeText(for feed: StockFeed) -> String {
        guard let quote = feed.quote else {
            return feed.error?.shortDescription ?? "Loading…"
        }
        if let error = feed.error, feed.isStale(maxAge: settings.refreshInterval, at: Date()) {
            return error.shortDescription
        }
        return settings.changeText(for: quote)
    }

    private func changeColor(for feed: StockFeed) -> Color {
        guard let quote = feed.quote, feed.error == nil || !feed.isStale(maxAge: settings.refreshInterval, at: Date())
        else { return .secondary }
        return StockStyle.color(for: quote.move)
    }

    private func summary(for symbol: String) -> String {
        let feed = service.feed(for: symbol)
        guard let quote = feed.quote else {
            return "\(symbol): \(feed.error?.shortDescription ?? "loading")"
        }
        let change = StockFormatting.changeWithPercent(
            quote.change, fraction: quote.changeFraction, fractionDigits: quote.fractionDigits)
        return "\(symbol) \(priceText(for: feed)) \(change)"
    }

    private func helpText(for symbols: [String]) -> String {
        guard !symbols.isEmpty else { return "Stocks: add symbols in Settings" }
        var lines = symbols.prefix(Self.listRows * 2).map(summary(for:))
        if let fetchedAt = service.feed(for: symbols[0]).quote?.fetchedAt {
            lines.append("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
        }
        return lines.joined(separator: "\n")
    }

    private func accessibilityLabel(for symbols: [String]) -> String {
        guard !symbols.isEmpty else { return "Stocks: no symbols" }
        let shown =
            switch settings.style {
            case .single, .cycle: [symbols[0]]
            case .list: Array(symbols.prefix(Self.listRows))
            }
        return "Stocks: " + shown.map(summary(for:)).joined(separator: ", ")
    }
}
