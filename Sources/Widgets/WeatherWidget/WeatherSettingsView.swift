import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Settings for one weather tile: units, caption, and where the weather is for.
struct WeatherSettingsView: View {
    @Environment(\.widgetUpdateSettings) private var updater
    @State private var instance: WidgetInstance
    @State private var service = WeatherService.shared

    /// True while the user has picked "City", even before choosing one.
    @State private var usesCity: Bool
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    init(instance: WidgetInstance) {
        _instance = State(initialValue: instance)
        _usesCity = State(initialValue: WeatherLocationSettings.location(from: instance.settings).place != nil)
    }

    private var settings: WeatherSettings { WeatherSettings(instance: instance) }

    var body: some View {
        Form {
            Picker(
                "Temperature",
                selection: updater.choiceBinding(
                    WeatherSettings.unit, in: $instance, default: TemperatureUnit.preferred())
            ) {
                Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
            }

            Picker(
                "Caption", selection: updater.choiceBinding(WeatherSettings.caption, in: $instance, default: .location)
            ) {
                Text("Location name").tag(WeatherSettings.Caption.location)
                Text("Conditions").tag(WeatherSettings.Caption.condition)
            }

            Picker("Location", selection: usesCityBinding) {
                Text("Current Location").tag(false)
                Text("City").tag(true)
            }

            if usesCity {
                citySection
            } else {
                locationServicesStatus
            }

            Link(OpenMeteoClient.attribution, destination: OpenMeteoClient.attributionURL)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: query) {
            await search()
        }
    }

    // MARK: City

    @ViewBuilder
    private var citySection: some View {
        if let place = settings.location.place {
            LabeledContent("Showing", value: place.fullName)
        }

        TextField("Search for a city", text: $query, prompt: Text("City name"))
            .textFieldStyle(.roundedBorder)

        if isSearching {
            ProgressView().controlSize(.small)
        } else if searchFailed {
            WidgetCaption("Couldn't search. Check your internet connection and try again.")
        } else if !results.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(results) { place in
                    Button {
                        choose(place)
                    } label: {
                        HStack {
                            Text(place.fullName).lineLimit(1)
                            Spacer()
                            if settings.location.place == place {
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
            WidgetCaption("No places found.")
        }
    }

    private func choose(_ place: WeatherPlace) {
        WeatherLocationSettings.write(.place(place), into: &instance.settings)
        updater(instance)
        query = ""
        results = []
    }

    /// Looks the query up after a short pause, so typing doesn't fire a request per keystroke.
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        searchFailed = false
        guard usesCity, trimmed.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await service.searchPlaces(trimmed)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            results = []
            searchFailed = true
        }
    }

    // MARK: Location Services

    @ViewBuilder
    private var locationServicesStatus: some View {
        switch service.locationAuthorization {
        case .notDetermined:
            LabeledContent("Location access") {
                Button("Allow") {
                    Task { await service.requestLocationAccess() }
                }
            }
        case .denied:
            LabeledContent("Location access") {
                Button("Open Privacy Settings") {
                    WeatherPopoutView.openLocationPrivacySettings()
                }
            }
            WidgetCaption(
                "Location access is off, so the tile can't find your weather. Allow it, or pick a city instead.")
        case .authorized:
            EmptyView()
        }
    }

    // MARK: Bindings

    private var usesCityBinding: Binding<Bool> {
        Binding(
            get: { usesCity },
            set: { newValue in
                usesCity = newValue
                guard !newValue else { return }
                // Back to the current location right away; a city only takes effect once chosen.
                WeatherLocationSettings.write(.current, into: &instance.settings)
                updater(instance)
                results = []
                query = ""
            }
        )
    }
}
