import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// The watchlist in full, shown when the tile is clicked: one symbol's quote and chart
/// with range tabs, then every symbol as a row to pick from.
struct StocksPopoutView: View {
    let instance: WidgetInstance

    @State private var service = StocksService.shared
    @State private var selected: String?
    @State private var range: StockChartRange = .oneDay

    private var settings: StocksSettings { StocksSettings(instance: instance) }
    private var symbols: [String] { settings.symbols }

    /// The symbol the chart is for: the picked one while it's still on the list, else the first.
    private var shownSymbol: String? {
        if let selected, symbols.contains(selected) { return selected }
        return symbols.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let symbol = shownSymbol {
                let feed = service.feed(for: symbol)
                header(feed)
                rangeTabs
                StockChartView(chart: feed.chart(for: range), session: feed.quote?.regularSession)
                    .frame(height: 110)
                chartCaption(feed)
                if let error = feed.error {
                    problem(error)
                }
                if symbols.count > 1 {
                    Divider()
                    watchlist
                }
            } else {
                emptyState
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        // Today's quotes for the whole list, then the chart for the picked range. The popover
        // is only ever open while the dock is on screen, so there's no visibility check.
        .task(id: symbols) {
            await service.refresh(symbols, maxAge: settings.refreshInterval)
        }
        .task(id: ChartKey(symbol: shownSymbol, range: range)) {
            guard let symbol = shownSymbol else { return }
            await service.feed(for: symbol).refresh(range: range, maxAge: StocksService.chartRefreshInterval)
        }
    }

    private struct ChartKey: Equatable {
        var symbol: String?
        var range: StockChartRange
    }

    // MARK: Sections

    private func header(_ feed: StockFeed) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(feed.quote?.name ?? feed.symbol)
                    .font(.headline)
                    .lineLimit(1)
                Text([feed.symbol, feed.quote?.exchange].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let quote = feed.quote {
                    Text(
                        StockFormatting.price(
                            quote.price, currency: quote.currency, fractionDigits: quote.fractionDigits)
                    )
                    .font(.system(size: 28, weight: .light, design: .rounded))
                    .monospacedDigit()
                    Text(
                        StockFormatting.changeWithPercent(
                            quote.change, fraction: quote.changeFraction, fractionDigits: quote.fractionDigits)
                    )
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(StockStyle.color(for: quote.move))
                } else if feed.error == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("—")
                        .font(.system(size: 28, weight: .light, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rangeTabs: some View {
        Picker("Range", selection: $range) {
            ForEach(StockChartRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }

    /// What the chart covers, its move, and the market's state.
    @ViewBuilder
    private func chartCaption(_ feed: StockFeed) -> some View {
        let now = Date()
        HStack(spacing: 10) {
            if let chart = feed.chart(for: range) {
                let digits = feed.quote?.fractionDigits ?? 2
                if range != .oneDay, let change = chart.change {
                    Text(
                        StockFormatting.changeWithPercent(
                            change, fraction: chart.changeFraction, fractionDigits: digits)
                            + " over \(range.description)"
                    )
                    .foregroundStyle(StockStyle.color(for: StockMove(change: change)))
                    .monospacedDigit()
                } else if let quote = feed.quote {
                    Text(marketStateText(quote, at: now))
                }
                if let low = chart.low, let high = chart.high, chart.points.count > 1 {
                    Text("L \(Self.number(low, digits: digits))  H \(Self.number(high, digits: digits))")
                        .monospacedDigit()
                }
            } else if feed.isRefreshing {
                Text("Loading the chart…")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func marketStateText(_ quote: StockQuote, at now: Date) -> String {
        let time = quote.marketTime.formatted(date: .omitted, time: .shortened)
        if quote.isMarketOpen(at: now) {
            return "Market open · last trade \(time)"
        }
        let sameDay = Calendar.current.isDate(quote.marketTime, inSameDayAs: now)
        let when = sameDay ? time : quote.marketTime.formatted(date: .abbreviated, time: .omitted)
        return "Market closed · at close \(when)"
    }

    private func problem(_ error: StockFeedError) -> some View {
        Label(error.description, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var watchlist: some View {
        VStack(spacing: 2) {
            ForEach(symbols, id: \.self) { symbol in
                let feed = service.feed(for: symbol)
                Button {
                    selected = symbol
                } label: {
                    row(feed)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(symbol == shownSymbol ? Color.primary.opacity(0.08) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(rowAccessibilityLabel(feed))
            }
        }
    }

    private func row(_ feed: StockFeed) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(feed.symbol)
                    .font(.callout.weight(.semibold))
                Text(feed.quote?.name ?? feed.error?.shortDescription ?? "Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let quote = feed.quote {
                Text(StockFormatting.price(quote.price, currency: quote.currency, fractionDigits: quote.fractionDigits))
                    .font(.callout)
                    .monospacedDigit()
                Text(settings.changeText(for: quote))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(quote.move == .flat ? Color.secondary : .white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .frame(minWidth: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(StockStyle.color(for: quote.move).opacity(quote.move == .flat ? 0.15 : 0.85))
                    )
            } else {
                Text("—")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rowAccessibilityLabel(_ feed: StockFeed) -> String {
        guard let quote = feed.quote else { return "\(feed.symbol): \(feed.error?.shortDescription ?? "loading")" }
        let price = StockFormatting.price(quote.price, currency: quote.currency, fractionDigits: quote.fractionDigits)
        return "\(quote.name), \(price), \(settings.changeText(for: quote))"
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Stocks").font(.headline)
            Text("No symbols yet. Add some in this widget's settings.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await service.refresh(symbols, maxAge: settings.refreshInterval, force: true) }
                }
                .disabled(!canRefresh)

                if StockStyle.stocksAppURL != nil {
                    Button("Open Stocks") {
                        StockStyle.openInStocks(shownSymbol)
                    }
                }
            }
            .controlSize(.small)

            HStack {
                if let fetchedAt = shownSymbol.flatMap({ service.feed(for: $0).quote?.fetchedAt }) {
                    Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                Link(YahooFinanceClient.attribution, destination: YahooFinanceClient.attributionURL)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    /// Refresh does something only when some symbol hasn't been asked for in the last minute.
    private var canRefresh: Bool {
        let now = Date()
        return symbols.contains { symbol in
            let feed = service.feed(for: symbol)
            return !feed.isRefreshing && feed.canForceRefresh(at: now)
        }
    }

    // MARK: Formatting

    private static func number(_ value: Double, digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(max(0, min(digits, 4)))))
    }
}
