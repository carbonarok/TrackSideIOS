import SwiftUI
import SwiftData

struct JourneyHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JourneyRecord.completedAt, order: .reverse) private var records: [JourneyRecord]

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Completed tracked journeys will appear here")
                }
            } else {
                List {
                    ForEach(records) { record in
                        recordRow(record)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(records[index])
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Journey History")
    }

    @ViewBuilder
    private func recordRow(_ record: JourneyRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Route
            HStack {
                Text(record.routeName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if record.wasCancelled {
                    Text("Cancelled")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else if record.maxDelayMinutes > 0 {
                    Text("+\(record.maxDelayMinutes) min")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(record.maxDelayMinutes >= 10 ? .red : .orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((record.maxDelayMinutes >= 10 ? Color.red : .orange).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    Text("On time")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            // Time and date
            HStack(spacing: 12) {
                if let dep = record.scheduledDeparture {
                    Label(formatTime(dep), systemImage: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let arr = record.actualArrival ?? record.scheduledArrival {
                    Label(formatTime(arr), systemImage: "arrow.down.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(formatDate(record.completedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Leg details
            if !record.legSummaries.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(record.legSummaries.enumerated()), id: \.offset) { _, leg in
                        HStack(spacing: 3) {
                            Text(leg.headcode)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                            if leg.cancelled {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    Text("\(record.totalLegs) train\(record.totalLegs == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(identifier: "Europe/London")
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
