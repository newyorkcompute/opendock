import AppKit
import DockCore
import DockWidgetKit
import SwiftUI
import SystemServices

/// Conditions, the next hours, and the next days, shown when the weather tile is clicked.
struct WeatherPopoutView: View {
    let instance: WidgetInstance

    @State private var service = WeatherService.shared

    private var settings: WeatherSettings { WeatherSettings(instance: instance) }
    private var unit: TemperatureUnit { settings.unit }

    var body: some View {
        let feed = service.feed(for: settings.location)
        VStack(alignment: .leading, spacing: 12) {
            if let report = feed.report {
                header(report)
                details(report)
                if let error = feed.error {
                    problem(error)
                }
                Divider()
                hours(report)
                Divider()
                days(report)
            } else {
                emptyState(feed)
            }

            Divider()

            footer(feed)
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .task(id: settings.location) {
            await feed.refresh()
        }
    }

    // MARK: Sections

    private func header(_ report: WeatherReport) -> some View {
        HStack(alignment: .top, spacing: 12) {
            WeatherSymbol(name: report.current.symbolName, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.place.name.isEmpty ? WeatherWidget.displayName : report.place.fullName)
                    .font(.headline)
                    .lineLimit(1)
                Text(report.current.condition.description)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(unit.format(celsius: report.current.temperatureCelsius))
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .monospacedDigit()
                if let today = report.today(at: Date()) {
                    Text("H \(unit.format(celsius: today.highCelsius))  L \(unit.format(celsius: today.lowCelsius))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func details(_ report: WeatherReport) -> some View {
        HStack(spacing: 14) {
            if let feelsLike = report.current.apparentTemperatureCelsius {
                Label("Feels like \(unit.format(celsius: feelsLike))", systemImage: "thermometer.medium")
            }
            if let humidity = report.current.humidity {
                Label("\(humidity)%", systemImage: "humidity.fill")
            }
            if let wind = report.current.windSpeedKilometersPerHour {
                Label(Self.windText(kilometersPerHour: wind), systemImage: "wind")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private func problem(_ error: WeatherFeedError) -> some View {
        Label(error.description, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func hours(_ report: WeatherReport) -> some View {
        let now = Date()
        let hours = report.upcomingHours(from: now, limit: 12)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(hours.enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 4) {
                        Text(index == 0 ? "Now" : Self.hourText(hour.time, in: report.timeZone))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        WeatherSymbol(name: hour.symbolName, size: 16)
                        Text(unit.format(celsius: hour.temperatureCelsius))
                            .font(.callout)
                            .monospacedDigit()
                        if let chance = hour.precipitationProbability, chance >= 20 {
                            Text("\(chance)%")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                    .frame(minWidth: 36)
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityLabel("Hourly forecast")
    }

    private func days(_ report: WeatherReport) -> some View {
        let now = Date()
        return VStack(spacing: 6) {
            ForEach(Array(report.daily.prefix(4).enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 10) {
                    Text(index == 0 ? "Today" : Self.dayText(day.date, in: report.timeZone))
                        .frame(width: 64, alignment: .leading)
                    WeatherSymbol(name: day.condition.symbolName(isDay: true), size: 14)
                    Text(day.condition.description)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(unit.format(celsius: day.lowCelsius))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                    Text(unit.format(celsius: day.highCelsius))
                        .frame(width: 36, alignment: .trailing)
                }
                .font(.callout)
                .monospacedDigit()
                .opacity(day.date.addingTimeInterval(86_400) > now ? 1 : 0.5)
            }
        }
        .accessibilityLabel("Daily forecast")
    }

    @ViewBuilder
    private func emptyState(_ feed: WeatherFeed) -> some View {
        if let error = feed.error {
            Label(error.description, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(feed.location == .current ? "Finding your location…" : "Loading the weather…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func footer(_ feed: WeatherFeed) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button("Refresh") {
                    Task { await feed.refresh(force: true) }
                }
                .disabled(feed.isRefreshing)

                if settings.location == .current {
                    switch service.locationAuthorization {
                    case .notDetermined:
                        Button("Allow Location Access") {
                            Task {
                                await service.requestLocationAccess()
                                await feed.refresh(force: true)
                            }
                        }
                    case .denied:
                        Button("Open Privacy Settings") {
                            Self.openLocationPrivacySettings()
                        }
                    case .authorized:
                        EmptyView()
                    }
                }

                if let weatherApp = Self.weatherAppURL {
                    Button("Open Weather") {
                        NSWorkspace.shared.openApplication(
                            at: weatherApp, configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
            .controlSize(.small)

            HStack {
                if let report = feed.report {
                    Text("Updated \(report.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                Link(OpenMeteoClient.attribution, destination: OpenMeteoClient.attributionURL)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Formatting

    private static func hourText(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).hour(.defaultDigits(amPM: .abbreviated)))
    }

    private static func dayText(_ date: Date, in timeZone: TimeZone) -> String {
        date.formatted(Date.FormatStyle(timeZone: timeZone).weekday(.abbreviated))
    }

    /// Wind in the locale's unit: "12 mph" in the US, "19 km/h" elsewhere.
    static func windText(kilometersPerHour: Double) -> String {
        let speed = Measurement(value: kilometersPerHour, unit: UnitSpeed.kilometersPerHour)
        return speed.formatted(
            .measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0)))
        )
    }

    /// Apple's Weather app, which ships with macOS 14 and later.
    private static var weatherAppURL: URL? {
        let url = URL(fileURLWithPath: "/System/Applications/Weather.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func openLocationPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
