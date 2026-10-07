import Foundation
import Observation

/// A single leg in a calculated journey
struct CalculatedLeg: Identifiable {
    let id = UUID()
    let legIndex: Int
    let service: BoardService
    let serviceDetail: ServiceDetail?
    let originName: String
    let destinationName: String
    let departureTime: String?
    let arrivalTime: String?
    let departurePlatform: String?
    let arrivalPlatform: String?
    let departureDelay: Int?
    let arrivalDelay: Int?
    let isCancelled: Bool
    /// Minutes waiting at this station before this leg departs (nil for first leg)
    let connectionMinutes: Int?

    /// Find the stop at the destination within the service detail
    static func arrivalStop(in detail: ServiceDetail, destinationCode: String) -> Stop? {
        detail.stops.last { stop in
            stop.crs == destinationCode || stop.tiploc == destinationCode
        }
    }
}

/// A fully calculated journey across all legs of a route
struct CalculatedJourney {
    let legs: [CalculatedLeg]
    let departureTime: String?
    let arrivalTime: String?
    let requestedTime: Date

    var totalLegs: Int { legs.count }

    var hasIssues: Bool {
        legs.contains { $0.isCancelled } || legs.isEmpty
    }

    /// Try to compute total journey minutes from first departure to last arrival
    var totalMinutes: Int? {
        guard let first = legs.first?.departureTime,
              let last = legs.last?.arrivalTime else { return nil }
        guard let firstDate = parseTime(first),
              let lastDate = parseTime(last) else { return nil }
        let interval = lastDate.timeIntervalSince(firstDate)
        return max(0, Int(interval / 60))
    }
}

/// Calculates optimal journey for a saved route at a given time
@Observable
final class JourneyCalculator {
    var journey: CalculatedJourney?
    var isCalculating = false
    var error: String?

    private let apiClient = APIClient()

    func calculate(route: SavedRoute, departAt: Date) async {
        isCalculating = true
        error = nil
        journey = nil

        let connectionBuffer = TimeInterval(LiveActivitySettings.load().minimumConnectionMinutes * 60)

        let sortedLegs = route.sortedLegs
        guard !sortedLegs.isEmpty else {
            error = "Route has no legs"
            isCalculating = false
            return
        }

        var calculatedLegs: [CalculatedLeg] = []
        var nextEarliestDeparture = departAt

        for (index, leg) in sortedLegs.enumerated() {
            guard let destCode = leg.destinationCode, !destCode.isEmpty else {
                error = "Leg \(index + 1) has no destination set"
                isCalculating = false
                return
            }

            // Fetch departures from this leg's origin, filtered to destination
            let atString = formatForAPI(nextEarliestDeparture)
            let board: Board?
            do {
                board = try await apiClient.departures(
                    for: leg.originCode,
                    to: destCode,
                    at: atString,
                    window: 120
                )
            } catch {
                self.error = "Failed to load departures for \(leg.originName): \(error.localizedDescription)"
                isCalculating = false
                return
            }

            guard let board else {
                error = "No departures found from \(leg.originName)"
                isCalculating = false
                return
            }

            // Filter services by preferred platforms
            let depPlatforms = parsePlatforms(leg.preferredDeparturePlatform)
            let matchingServices = board.services.filter { service in
                // Must not be cancelled
                if service.isCancelled { return false }
                // Must depart at or after our earliest time
                if let depTime = service.stop.departure?.bestTime ?? service.stop.departure?.`public`,
                   let depDate = parseTime(depTime),
                   depDate < nextEarliestDeparture {
                    return false
                }
                // Platform filter
                if !depPlatforms.isEmpty {
                    let currentPlatform = service.stop.platform?.displayPlatform ?? ""
                    if !currentPlatform.isEmpty && !depPlatforms.contains(currentPlatform) {
                        return false
                    }
                }
                return true
            }

            guard let bestService = matchingServices.first else {
                error = "No suitable train found from \(leg.originName) to \(leg.destinationName ?? destCode) after \(formatDisplayTime(nextEarliestDeparture))"
                isCalculating = false
                return
            }

            // Fetch service detail to get arrival time at destination
            var serviceDetail: ServiceDetail?
            do {
                serviceDetail = try await apiClient.serviceDetail(uid: bestService.uid, date: bestService.runDate)
            } catch {
                // Continue without detail — we just won't have arrival info
            }

            // Extract arrival at destination from service detail
            let arrStop = serviceDetail.flatMap { CalculatedLeg.arrivalStop(in: $0, destinationCode: destCode) }
            let arrivalTime = arrStop?.arrival?.bestTime ?? arrStop?.arrival?.`public`
            let arrivalPlatform = arrStop?.platform?.displayPlatform
            let arrivalDelay = arrStop?.arrival?.delayMinutes

            // Check arrival platform filter — if the user specified preferred arrival
            // platforms and the service arrives at a different one, skip and try next
            let arrPlatforms = parsePlatforms(leg.preferredArrivalPlatform)
            if !arrPlatforms.isEmpty, let actualArrPlatform = arrivalPlatform,
               !actualArrPlatform.isEmpty, !arrPlatforms.contains(actualArrPlatform) {
                // This service doesn't arrive at the preferred platform — try next
                let remaining = matchingServices.dropFirst()
                var foundAlternative = false
                for altService in remaining {
                    if let altDetail = try? await apiClient.serviceDetail(uid: altService.uid, date: altService.runDate),
                       let altArrStop = CalculatedLeg.arrivalStop(in: altDetail, destinationCode: destCode),
                       let altArrPlatform = altArrStop.platform?.displayPlatform,
                       arrPlatforms.contains(altArrPlatform) {
                        // Use this alternative service instead — re-extract its data
                        let altArrivalTime = altArrStop.arrival?.bestTime ?? altArrStop.arrival?.`public`
                        let altArrivalDelay = altArrStop.arrival?.delayMinutes
                        let altConnectionMinutes: Int?
                        if index > 0, let prevArrival = calculatedLegs.last?.arrivalTime,
                           let prevDate = parseTime(prevArrival),
                           let depTime = altService.stop.departure?.bestTime ?? altService.stop.departure?.`public`,
                           let depDate = parseTime(depTime) {
                            altConnectionMinutes = max(0, Int(depDate.timeIntervalSince(prevDate) / 60))
                        } else {
                            altConnectionMinutes = nil
                        }

                        let altLeg = CalculatedLeg(
                            legIndex: index,
                            service: altService,
                            serviceDetail: altDetail,
                            originName: leg.originName,
                            destinationName: leg.destinationName ?? destCode,
                            departureTime: altService.stop.departure?.bestTime ?? altService.stop.departure?.`public`,
                            arrivalTime: altArrivalTime,
                            departurePlatform: altService.stop.platform?.displayPlatform,
                            arrivalPlatform: altArrPlatform,
                            departureDelay: altService.stop.departure?.delayMinutes,
                            arrivalDelay: altArrivalDelay,
                            isCancelled: altService.isCancelled,
                            connectionMinutes: altConnectionMinutes
                        )
                        calculatedLegs.append(altLeg)
                        if let altArrivalTime, let arrDate = parseTime(altArrivalTime) {
                            nextEarliestDeparture = arrDate.addingTimeInterval(connectionBuffer)
                        } else if let depTime = altService.stop.departure?.bestTime,
                                  let depDate = parseTime(depTime) {
                            nextEarliestDeparture = depDate.addingTimeInterval(30 * 60)
                        }
                        foundAlternative = true
                        break
                    }
                }
                if foundAlternative { continue }
                // No alternative found — use the original service anyway
            }

            // Calculate connection time from previous leg
            let connectionMinutes: Int?
            if index > 0, let prevArrival = calculatedLegs.last?.arrivalTime,
               let prevDate = parseTime(prevArrival),
               let depTime = bestService.stop.departure?.bestTime ?? bestService.stop.departure?.`public`,
               let depDate = parseTime(depTime) {
                connectionMinutes = max(0, Int(depDate.timeIntervalSince(prevDate) / 60))
            } else {
                connectionMinutes = nil
            }

            let calcLeg = CalculatedLeg(
                legIndex: index,
                service: bestService,
                serviceDetail: serviceDetail,
                originName: leg.originName,
                destinationName: leg.destinationName ?? destCode,
                departureTime: bestService.stop.departure?.bestTime ?? bestService.stop.departure?.`public`,
                arrivalTime: arrivalTime,
                departurePlatform: bestService.stop.platform?.displayPlatform,
                arrivalPlatform: arrivalPlatform,
                departureDelay: bestService.stop.departure?.delayMinutes,
                arrivalDelay: arrivalDelay,
                isCancelled: bestService.isCancelled,
                connectionMinutes: connectionMinutes
            )
            calculatedLegs.append(calcLeg)

            // Set next earliest departure: arrival time + connection buffer
            if let arrivalTime, let arrDate = parseTime(arrivalTime) {
                nextEarliestDeparture = arrDate.addingTimeInterval(connectionBuffer)
            } else if let depTime = bestService.stop.departure?.bestTime,
                      let depDate = parseTime(depTime) {
                // Fallback: estimate 30 min travel, then connect
                nextEarliestDeparture = depDate.addingTimeInterval(30 * 60)
            }
        }

        journey = CalculatedJourney(
            legs: calculatedLegs,
            departureTime: calculatedLegs.first?.departureTime,
            arrivalTime: calculatedLegs.last?.arrivalTime,
            requestedTime: departAt
        )
        isCalculating = false
    }

    // MARK: - Helpers

    private func parsePlatforms(_ value: String?) -> Set<String> {
        guard let value, !value.isEmpty else { return [] }
        return Set(value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// Format a Date for the API `at` parameter (UK local time)
    private func formatForAPI(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }

    private func formatDisplayTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }
}

// MARK: - Time parsing helpers (module-level)

/// Parse an ISO 8601 or HH:MM time string into a Date (today, UK timezone)
func parseTime(_ timeString: String) -> Date? {
    // Try ISO 8601 first: 2026-10-06T14:32:00+01:00
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    if let date = iso.date(from: timeString) {
        return date
    }

    // Try with fractional seconds
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: timeString) {
        return date
    }

    // Try HH:MM format (assume today, UK timezone)
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(identifier: "Europe/London")

    if timeString.count == 5 {
        formatter.dateFormat = "HH:mm"
        if let time = formatter.date(from: timeString) {
            // Combine with today's date
            let calendar = Calendar.current
            let now = Date()
            var components = calendar.dateComponents(in: formatter.timeZone!, from: now)
            let timeComponents = calendar.dateComponents(in: formatter.timeZone!, from: time)
            components.hour = timeComponents.hour
            components.minute = timeComponents.minute
            components.second = 0
            return calendar.date(from: components)
        }
    }

    return nil
}
