import SwiftUI

struct LegEditorView: View {
    @Binding var originCode: String
    @Binding var originName: String
    @Binding var destinationCode: String
    @Binding var destinationName: String
    @Binding var departurePlatforms: String
    @Binding var arrivalPlatforms: String

    var onSearchOrigin: () -> Void
    var onSearchDestination: () -> Void

    @State private var newDepPlatform = ""
    @State private var newArrPlatform = ""

    var body: some View {
        // Origin
        HStack {
            Label("From", systemImage: "location.fill")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onSearchOrigin) {
                if originName.isEmpty {
                    Text("Select station")
                        .foregroundStyle(.blue)
                } else {
                    VStack(alignment: .trailing) {
                        Text(originName)
                        if !originCode.isEmpty {
                            Text(originCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .tint(.primary)
        }

        // Departure platforms
        platformEditor(
            label: "Dep. Platforms",
            platforms: $departurePlatforms,
            newPlatform: $newDepPlatform
        )

        // Destination
        HStack {
            Label("To", systemImage: "mappin")
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: onSearchDestination) {
                if destinationName.isEmpty {
                    Text("Select station")
                        .foregroundStyle(.blue)
                } else {
                    VStack(alignment: .trailing) {
                        Text(destinationName)
                        if !destinationCode.isEmpty {
                            Text(destinationCode)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .tint(.primary)
        }

        // Arrival platforms
        platformEditor(
            label: "Arr. Platforms",
            platforms: $arrivalPlatforms,
            newPlatform: $newArrPlatform
        )
    }

    @ViewBuilder
    private func platformEditor(label: String, platforms: Binding<String>, newPlatform: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: "rectangle.split.3x1")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let platformList = parsePlatforms(platforms.wrappedValue)

            if !platformList.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(platformList, id: \.self) { plat in
                        HStack(spacing: 4) {
                            Text(plat)
                                .font(.caption)
                                .fontWeight(.medium)
                            Button {
                                removePlatform(plat, from: platforms)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .tint(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                TextField("Add platform", text: newPlatform)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)

                Button("Add") {
                    let trimmed = newPlatform.wrappedValue.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    addPlatform(trimmed, to: platforms)
                    newPlatform.wrappedValue = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(newPlatform.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()

                if !platformList.isEmpty {
                    Text("Any of \(platformList.count)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func parsePlatforms(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        return value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func addPlatform(_ platform: String, to binding: Binding<String>) {
        var list = parsePlatforms(binding.wrappedValue)
        if !list.contains(platform) {
            list.append(platform)
        }
        binding.wrappedValue = list.joined(separator: ",")
    }

    private func removePlatform(_ platform: String, from binding: Binding<String>) {
        var list = parsePlatforms(binding.wrappedValue)
        list.removeAll { $0 == platform }
        binding.wrappedValue = list.joined(separator: ",")
    }
}

/// Simple horizontal wrapping layout for platform chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
