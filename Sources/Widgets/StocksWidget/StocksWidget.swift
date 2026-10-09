import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// A watchlist of stock, index, currency, and crypto symbols with prices and the day's
/// move, from Yahoo Finance. The settings keys are declared in `StocksSettings` and listed
/// in `docs/widgets.md`; the symbol list is parsed by `StockSymbols` in `SystemServices`.
public enum StocksWidget: DockWidget {
    public static let typeID = BuiltInWidgetID.stocks
    public static let displayName = "Stocks"
    public static let systemImage = "chart.line.uptrend.xyaxis"
    public static let summary = "Prices and the day's change for a watchlist."
    public static let settingsSchema = StocksSettings.schema

    public static func makeView(instance: WidgetInstance) -> AnyView {
        AnyView(StocksTileView(instance: instance))
    }

    public static func makePopout(instance: WidgetInstance) -> AnyView? {
        AnyView(StocksPopoutView(instance: instance))
    }

    public static func makeSettingsView(instance: WidgetInstance) -> AnyView? {
        AnyView(StocksSettingsView(instance: instance))
    }
}

/// The stocks widget's settings keys, and typed access to one instance's values.
struct StocksSettings {
    /// What the tile shows.
    enum Style: String, CaseIterable {
        /// The first symbol: price, change, and the day's line.
        case single
        /// Each symbol in turn, a few seconds at a time.
        case cycle
        /// Every symbol's change on its own row.
        case list
    }

    enum ChangeFormat: String, CaseIterable {
        case percent
        case amount
    }

    static let symbols = WidgetSettingKey(
        "symbols", type: .text, default: "AAPL, MSFT, ^GSPC",
        summary:
            "The symbols to watch, separated by commas, as Yahoo Finance writes them: `\"AAPL\"`, `\"BRK-B\"`, `\"^GSPC\"` for the S&P 500, `\"EURUSD=X\"` for a currency pair, `\"BTC-USD\"` for Bitcoin. Up to 20."
    )
    static let style = WidgetSettingKey(
        "style", type: .choice(Style.allCases.map(\.rawValue)), default: Style.single.rawValue,
        summary:
            "What the tile shows: the first symbol with its price and change (`\"single\"`), each symbol in turn for a few seconds at a time (`\"cycle\"`), or every symbol's change on its own row (`\"list\"`)."
    )
    static let change = WidgetSettingKey(
        "change", type: .choice(ChangeFormat.allCases.map(\.rawValue)), default: ChangeFormat.percent.rawValue,
        summary: "Show the day's move as a percentage, or as an amount in the symbol's currency.")
    static let showChart = WidgetSettingKey(
        "showChart", type: .bool, default: "true",
        summary: "Draw the day's price line beside the quote. The list style has no room for it.")
    static let refreshMinutes = WidgetSettingKey(
        "refreshMinutes", type: .integer(1 ... 60), default: "5",
        summary:
            "How often to fetch new quotes while the dock is visible, in minutes. A hidden dock fetches nothing, and no symbol is fetched more than once a minute."
    )

    static let schema = WidgetSettingsSchema([symbols, style, change, showChart, refreshMinutes])

    let instance: WidgetInstance

    var symbols: [String] { StockSymbols.parse(Self.symbols.value(in: instance.settings)) }
    var style: Style { Style(rawValue: Self.style.value(in: instance.settings)) ?? .single }
    var changeFormat: ChangeFormat { ChangeFormat(rawValue: Self.change.value(in: instance.settings)) ?? .percent }
    var showsChart: Bool { Self.showChart.boolValue(in: instance.settings) }
    var refreshInterval: Duration { .seconds(60 * Self.refreshMinutes.intValue(in: instance.settings)) }

    /// The move as the tile shows it: "+0.54%" or "+1.23".
    func changeText(for quote: StockQuote) -> String {
        switch changeFormat {
        case .percent: StockFormatting.percent(quote.changeFraction)
        case .amount: StockFormatting.change(quote.change, fractionDigits: quote.fractionDigits)
        }
    }
}

/// Colors shared by the tile and the popover.
enum StockStyle {
    static func color(for move: StockMove) -> Color {
        switch move {
        case .up: .green
        case .down: .red
        case .flat: .secondary
        }
    }

    /// Apple's Stocks app, which ships with macOS 10.14 and later.
    static var stocksAppURL: URL? {
        let url = URL(fileURLWithPath: "/System/Applications/Stocks.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Opens `symbol` in the Stocks app, or just the app when it doesn't take the URL.
    static func openInStocks(_ symbol: String?) {
        if let encoded = symbol?.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
            let url = URL(string: "stocks://?symbol=\(encoded)"), NSWorkspace.shared.open(url)
        {
            return
        }
        if let app = stocksAppURL {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
