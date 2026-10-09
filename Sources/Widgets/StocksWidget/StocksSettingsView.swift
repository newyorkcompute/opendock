import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one stocks tile: the watchlist, with search to add to it, and how the
/// tile shows it.
struct StocksSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var service = StocksService.shared

    @State private var query = ""
    @State private var results: [StockSearchResult] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    private static let refreshChoices = [1, 2, 5, 10, 15, 30, 60]

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
    }

    private var settings: StocksSettings { StocksSettings(instance: instance) }
    private var symbols: [String] { settings.symbols }

    var body: some View {
        Form {
            watchlist

            Picker("Show", selection: updater.stringBinding(StocksSettings.style, in: $instance)) {
                Text("First symbol").tag(StocksSettings.Style.single.rawValue)
                Text("Each symbol in turn").tag(StocksSettings.Style.cycle.rawValue)
                Text("List of changes").tag(StocksSettings.Style.list.rawValue)
            }

            Picker("Change", selection: updater.stringBinding(StocksSettings.change, in: $instance)) {
                Text("Percent").tag(StocksSettings.ChangeFormat.percent.rawValue)
                Text("Amount").tag(StocksSettings.ChangeFormat.amount.rawValue)
            }

            Toggle("Show chart", isOn: updater.boolBinding(StocksSettings.showChart, in: $instance))

            Picker("Refresh", selection: updater.stringBinding(StocksSettings.refreshMinutes, in: $instance)) {
                ForEach(refreshChoices, id: \.self) { minutes in
                    Text(minutes == 1 ? "Every minute" : "Every \(minutes) minutes").tag(String(minutes))
                }
            }

            Text("Quotes are delayed by up to 15 minutes on most exchanges and fetched only while the dock is visible.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link(YahooFinanceClient.attribution, destination: YahooFinanceClient.attributionURL)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: query) {
            await search()
        }
    }

    /// The usual choices, plus the stored value when a hand-edited file has another.
    private var refreshChoices: [Int] {
        let stored = StocksSettings.refreshMinutes.intValue(in: instance.settings)
        return Self.refreshChoices.contains(stored) ? Self.refreshChoices : (Self.refreshChoices + [stored]).sorted()
    }

    // MARK: Watchlist

    @ViewBuilder
    private var watchlist: some View {
        LabeledContent("Symbols") {
            VStack(alignment: .leading, spacing: 4) {
                if symbols.isEmpty {
                    Text("None yet")
                        .foregroundStyle(.secondary)
                }
                ForEach(symbols, id: \.self) { symbol in
                    HStack(spacing: 6) {
                        Text(symbol)
                            .font(.body.weight(.medium))
                        Text(service.feed(for: symbol).quote?.name ?? "")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Button {
                            remove(symbol)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(symbol)")
                    }
                }
            }
        }

        TextField("Add", text: $query, prompt: Text("Company name or symbol"))
            .textFieldStyle(.roundedBorder)
            .onSubmit(addTyped)
            .disabled(symbols.count >= StockSymbols.maximumCount)

        if symbols.count >= StockSymbols.maximumCount {
            Text("The watchlist holds up to \(StockSymbols.maximumCount) symbols.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if isSearching {
            ProgressView().controlSize(.small)
        } else if searchFailed {
            Text("Couldn't search. Check your internet connection, or type the symbol and press Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !results.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(results) { result in
                    Button {
                        add(result.symbol)
                    } label: {
                        HStack(spacing: 6) {
                            Text(result.symbol)
                                .font(.body.weight(.medium))
                                .frame(minWidth: 56, alignment: .leading)
                            Text(result.name)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if symbols.contains(result.symbol) {
                                Image(systemName: "checkmark").foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        } else if query.trimmingCharacters(in: .whitespaces).count >= 2 {
            Text("No matches. Press Return to add the symbol as typed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func add(_ symbol: String) {
        guard let cleaned = StockSymbols.sanitize(symbol) else { return }
        var list = symbols
        if !list.contains(cleaned) { list.append(cleaned) }
        write(list)
        query = ""
        results = []
    }

    /// Return in the field adds the first match, or the text as a symbol when there's none.
    private func addTyped() {
        if let first = results.first {
            add(first.symbol)
        } else {
            add(query)
        }
    }

    private func remove(_ symbol: String) {
        write(symbols.filter { $0 != symbol })
    }

    private func write(_ list: [String]) {
        instance.settings[StocksSettings.symbols.name] = StockSymbols.storageValue(
            Array(list.prefix(StockSymbols.maximumCount)))
        updater(instance)
    }

    /// Looks the query up after a short pause, so typing doesn't fire a request per keystroke.
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchFailed = false
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await service.search(trimmed)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            results = []
            searchFailed = true
        }
    }
}
