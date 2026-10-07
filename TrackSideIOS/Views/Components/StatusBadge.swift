import SwiftUI

/// Displays service status as a colored pill
struct StatusBadge: View {
    let status: ServiceStatus
    let delayMinutes: Int?
    let cancelled: Bool
    let lateReason: String?

    init(status: ServiceStatus, delayMinutes: Int? = nil, cancelled: Bool = false, lateReason: String? = nil) {
        self.status = status
        self.delayMinutes = delayMinutes
        self.cancelled = cancelled
        self.lateReason = lateReason
    }

    var body: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }

    private var statusText: String {
        if cancelled || status == .cancelled {
            return "Cancelled"
        }
        if status == .partiallyCancelled {
            return "Part Cancelled"
        }
        if let delay = delayMinutes {
            if delay <= 0 { return "On time" }
            return "+\(delay) min"
        }
        switch status {
        case .scheduled: return "Scheduled"
        case .activated: return "Activated"
        case .running: return "Running"
        case .terminated: return "Arrived"
        default: return status.rawValue.capitalized
        }
    }

    private var statusColor: Color {
        if cancelled || status == .cancelled || status == .partiallyCancelled {
            return .red
        }
        if let delay = delayMinutes {
            if delay <= 0 { return .green }
            if delay < 5 { return .yellow }
            if delay < 10 { return .orange }
            return .red
        }
        switch status {
        case .running: return .blue
        case .terminated: return .green
        default: return .secondary
        }
    }
}
