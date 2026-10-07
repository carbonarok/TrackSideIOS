import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Configuration Intent

struct SelectStationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Station"
    static var description: IntentDescription = "Choose a station to show departures for"

    @Parameter(title: "Station Code", description: "The CRS code of the station (e.g. WAT, PAD, VIC)", default: "WAT")
    var stationCode: String?

    @Parameter(title: "Station Name", description: "Display name for the station", default: "London Waterloo")
    var stationName: String?
}

// MARK: - Timeline Entry

struct DepartureEntry: TimelineEntry {
    let date: Date
    let stationName: String
    let stationCode: String
    let departures: [WidgetDeparture]
    let errorMessage: String?

    struct WidgetDeparture: Identifiable {
        let id: String
        let headcode: String
        let destination: String
        let scheduledTime: String
        let expectedTime: String?
        let platform: String?
        let platformChanged: Bool
        let delayMinutes: Int
        let isCancelled: Bool
        let operatorCode: String?
    }
}

// MARK: - Timeline Provider

struct DepartureTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DepartureEntry {
        DepartureEntry(
            date: .now,
            stationName: "London Waterloo",
            stationCode: "WAT",
            departures: [
                .init(id: "1", headcode: "1A23", destination: "Woking", scheduledTime: "14:32", expectedTime: nil, platform: "3", platformChanged: false, delayMinutes: 0, isCancelled: false, operatorCode: "SW"),
                .init(id: "2", headcode: "2B45", destination: "Windsor & Eton Riverside", scheduledTime: "14:35", expectedTime: "14:38", platform: "7", platformChanged: false, delayMinutes: 3, isCancelled: false, operatorCode: "SW"),
                .init(id: "3", headcode: "1C67", destination: "Portsmouth Harbour", scheduledTime: "14:40", expectedTime: nil, platform: "11", platformChanged: false, delayMinutes: 0, isCancelled: false, operatorCode: "SW"),
            ],
            errorMessage: nil
        )
    }

    func snapshot(for configuration: SelectStationIntent, in context: Context) async -> DepartureEntry {
        if context.isPreview {
            return placeholder(in: context)
        }
        return await fetchDepartures(for: configuration)
    }

    func timeline(for configuration: SelectStationIntent, in context: Context) async -> Timeline<DepartureEntry> {
        let entry = await fetchDepartures(for: configuration)
        // Refresh every 2 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 2, to: .now)!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func fetchDepartures(for config: SelectStationIntent) async -> DepartureEntry {
        let code = (config.stationCode ?? "WAT").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let name = config.stationName ?? code
        guard !code.isEmpty else {
            return DepartureEntry(date: .now, stationName: name, stationCode: code, departures: [], errorMessage: "No station configured")
        }

        let baseURL = AppConfig.baseURL
        let url = baseURL.appendingPathComponent("v1/locations/\(code)/departures")

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return DepartureEntry(date: .now, stationName: name, stationCode: code, departures: [], errorMessage: "Failed to load")
            }

            let decoder = JSONDecoder()
            let board = try decoder.decode(WidgetBoard.self, from: data)
            let displayName = board.location.name
            let departures = Array(board.services.prefix(6)).map { svc in
                let dep = svc.stop.departure
                let scheduledTime = formatTime(dep?.public ?? dep?.working)
                let expectedTime = formatTime(dep?.actual ?? dep?.estimated)
                let delay = dep?.delayMinutes ?? 0

                return DepartureEntry.WidgetDeparture(
                    id: "\(svc.uid)|\(svc.runDate)",
                    headcode: svc.headcode ?? "????",
                    destination: svc.destination.first?.name ?? "Unknown",
                    scheduledTime: scheduledTime ?? "??:??",
                    expectedTime: delay > 0 ? expectedTime : nil,
                    platform: svc.stop.platform?.actual ?? svc.stop.platform?.planned,
                    platformChanged: svc.stop.platform?.changed ?? false,
                    delayMinutes: delay,
                    isCancelled: svc.status == "cancelled" || svc.status == "partially_cancelled" || svc.plannedCancel,
                    operatorCode: svc.operator?.code
                )
            }

            return DepartureEntry(date: .now, stationName: displayName, stationCode: code, departures: departures, errorMessage: nil)
        } catch {
            return DepartureEntry(date: .now, stationName: name, stationCode: code, departures: [], errorMessage: "Error loading departures")
        }
    }

    private func formatTime(_ isoString: String?) -> String? {
        guard let str = isoString else { return nil }
        // Extract HH:mm from ISO 8601 date-time string
        if let tIndex = str.firstIndex(of: "T") {
            let timeStr = str[str.index(after: tIndex)...]
            if timeStr.count >= 5 {
                return String(timeStr.prefix(5))
            }
        }
        // Fallback: if it's already HH:mm
        if str.count == 5 && str.contains(":") {
            return str
        }
        return nil
    }
}

// MARK: - Lightweight Decodable models for the widget

private struct WidgetBoard: Decodable {
    let location: WidgetLocation
    let services: [WidgetBoardService]
}

private struct WidgetLocation: Decodable {
    let name: String
    let crs: String?
}

private struct WidgetBoardService: Decodable {
    let uid: String
    let runDate: String
    let headcode: String?
    let `operator`: WidgetOperator?
    let status: String
    let destination: [WidgetEndpoint]
    let plannedCancel: Bool
    let stop: WidgetStop
}

private struct WidgetOperator: Decodable {
    let code: String
    let name: String
}

private struct WidgetEndpoint: Decodable {
    let name: String
}

private struct WidgetStop: Decodable {
    let departure: WidgetTimes?
    let platform: WidgetPlatform?
}

private struct WidgetTimes: Decodable {
    let `public`: String?
    let working: String?
    let actual: String?
    let estimated: String?
    let delayMinutes: Int?
}

private struct WidgetPlatform: Decodable {
    let planned: String?
    let actual: String?
    let changed: Bool
}

// MARK: - Widget Views

struct DepartureWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: DepartureEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        default:
            mediumView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                Text(entry.stationCode)
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
            }

            Text(entry.stationName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error = entry.errorMessage {
                Spacer()
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let first = entry.departures.first {
                Spacer()

                Text(first.destination)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(first.scheduledTime)
                        .font(.title2)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    if first.isCancelled {
                        Text("CANC")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.red))
                    } else if first.delayMinutes > 0 {
                        Text("+\(first.delayMinutes)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 4) {
                    if let plat = first.platform {
                        HStack(spacing: 2) {
                            Text("Plat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(plat)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundStyle(first.platformChanged ? .red : .primary)
                        }
                    }
                    Spacer()
                    Text(first.headcode)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Spacer()
                Text("No departures")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(entry.stationName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.stationCode)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            if let error = entry.errorMessage {
                Spacer()
                HStack {
                    Spacer()
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else if entry.departures.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No departures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(entry.departures.prefix(3))) { dep in
                    departureRow(dep)
                    if dep.id != entry.departures.prefix(3).last?.id {
                        Divider()
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Large Widget

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                Text(entry.stationName)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.stationCode)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            if let error = entry.errorMessage {
                Spacer()
                HStack {
                    Spacer()
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else if entry.departures.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    Text("No departures")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(entry.departures) { dep in
                    departureRow(dep)
                    if dep.id != entry.departures.last?.id {
                        Divider()
                            .padding(.vertical, 3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Row

    private func departureRow(_ dep: DepartureEntry.WidgetDeparture) -> some View {
        HStack(spacing: 8) {
            // Operator color stripe
            if let code = dep.operatorCode {
                RoundedRectangle(cornerRadius: 2)
                    .fill(operatorColor(code))
                    .frame(width: 3, height: 28)
            }

            // Time
            VStack(alignment: .leading, spacing: 0) {
                Text(dep.scheduledTime)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .strikethrough(dep.isCancelled)

                if dep.isCancelled {
                    Text("Cancelled")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                } else if let exp = dep.expectedTime {
                    Text(exp)
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }
            .frame(width: 44, alignment: .leading)

            // Destination
            VStack(alignment: .leading, spacing: 0) {
                Text(dep.destination)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(dep.headcode)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            // Platform
            if let plat = dep.platform {
                Text(plat)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(dep.platformChanged ? .red : .secondary)
                    .frame(minWidth: 20)
            }
        }
    }

    // MARK: - Operator Colors

    private func operatorColor(_ code: String) -> Color {
        switch code {
        case "GW": return .init(red: 0.0, green: 0.33, blue: 0.25)
        case "SW": return .init(red: 0.0, green: 0.22, blue: 0.53)
        case "VT": return .init(red: 0.53, green: 0.0, blue: 0.18)
        case "XC": return .init(red: 0.26, green: 0.0, blue: 0.33)
        case "SE": return .init(red: 0.0, green: 0.24, blue: 0.42)
        case "TL": return .init(red: 0.87, green: 0.24, blue: 0.51)
        case "GN": return .init(red: 0.14, green: 0.15, blue: 0.56)
        case "SN": return .init(red: 0.0, green: 0.39, blue: 0.20)
        case "TP": return .init(red: 0.0, green: 0.58, blue: 0.62)
        case "SR": return .init(red: 0.0, green: 0.22, blue: 0.53)
        case "EM": return .init(red: 0.27, green: 0.08, blue: 0.38)
        case "LM": return .init(red: 0.53, green: 0.74, blue: 0.0)
        case "GR": return .init(red: 0.73, green: 0.0, blue: 0.0)
        case "LE": return .init(red: 0.0, green: 0.34, blue: 0.66)
        case "CC": return .init(red: 0.0, green: 0.0, blue: 0.0)
        case "LO": return .init(red: 0.9, green: 0.4, blue: 0.0)
        case "HX": return .init(red: 0.27, green: 0.04, blue: 0.42)
        default: return .gray
        }
    }
}

// MARK: - Widget Definition

struct DepartureWidget: Widget {
    let kind = "DepartureWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: SelectStationIntent.self,
            provider: DepartureTimelineProvider()
        ) { entry in
            DepartureWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Departures")
        .description("See upcoming departures from your station")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
