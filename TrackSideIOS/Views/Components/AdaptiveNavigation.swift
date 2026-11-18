import SwiftUI

/// Every screen a tab can push. One type lets a tab's path be a plain array,
/// so it can be split into "the selected item" and "what's pushed on top"
/// when the layout changes.
enum AppDestination: Hashable {
    case service(ServiceRoute)
    case route(SavedRoute)
}

/// A list and the item it opens.
///
/// With room for both (iPhone Duo unfolded, iPad), they sit side by side.
/// Without it (iPhone, iPhone Duo folded) they're one stack, as before.
/// Both layouts read the same `path`, so folding or unfolding the phone keeps
/// whatever is open.
struct AdaptiveNavigation<Sidebar: View, Detail: View, Placeholder: View>: View {
    @Binding var path: [AppDestination]
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let destination: (AppDestination) -> Detail
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Where the fold runs, once found. Layout passes can briefly report
    /// none (mid-animation, say); switching layouts then would rebuild both
    /// pages and lose their state, so it's only dropped when the size changes.
    @State private var fold: CGFloat?
    /// The open item has both halves of an unfolded iPhone Duo, not just
    /// one; it lays itself out either side of the fold.
    @State private var usesBothHalves = false

    var body: some View {
        if horizontalSizeClass == .regular {
            split
        } else {
            NavigationStack(path: $path) {
                sidebar()
                    .navigationDestination(for: AppDestination.self, destination: destination)
            }
        }
    }

    private var split: some View {
        splitView
            .onGeometryChange(for: FoldReading.self) { proxy in
                FoldReading(position: Self.foldPosition(in: proxy), size: proxy.size)
            } action: { old, new in
                if new.position != nil || new.size != old.size {
                    fold = new.position
                }
            }
    }

    private nonisolated struct FoldReading: Equatable, Sendable {
        var position: CGFloat?
        var size: CGSize
    }

    /// The open item, spanning both halves of an unfolded iPhone Duo.
    private var spansFold: Bool {
        fold != nil && usesBothHalves && !path.isEmpty
    }

    private var bothHalvesButton: some View {
        Button {
            usesBothHalves.toggle()
        } label: {
            Label(
                usesBothHalves ? "Show the List" : "Use Both Halves",
                systemImage: usesBothHalves ? "sidebar.left" : "rectangle.split.2x1"
            )
        }
    }

    private var list: some View {
        sidebar()
            .environment(\.openDestination, OpenDestinationAction(selected: path.first) { path = [$0] })
    }

    /// The selected item is the root of the detail column, so it has no
    /// back button. Anything it opens is pushed on top.
    private var detail: some View {
        NavigationStack(path: pushedOnSelection) {
            Group {
                if let selected = path.first {
                    destination(selected)
                        // A new selection is a new screen, not an update to the old one.
                        .id(selected)
                } else {
                    placeholder()
                }
            }
            .toolbar {
                // Only beside a fold, and only with something open.
                if fold != nil && !path.isEmpty && !usesBothHalves {
                    ToolbarItem(placement: .primaryAction) {
                        bothHalvesButton
                    }
                }
            }
            .navigationDestination(for: AppDestination.self, destination: destination)
        }
    }

    /// The list as a sidebar beside the open item. With "Use Both Halves"
    /// the sidebar steps aside and the item spans the fold, splitting
    /// itself there.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: .constant(spansFold ? .detailOnly : .all)) {
            list
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
                // Both columns stay on screen: hiding the list would leave
                // nothing to choose from, only "No Train Selected".
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .environment(\.spanningFold, spansFold ? fold : nil)
                // Spanning, the way back floats over the page: a page split
                // into two lists loses toolbar items the system puts in
                // the side bar.
                .overlay(alignment: .bottomLeading) {
                    if spansFold {
                        bothHalvesButton
                            .labelStyle(.titleAndIcon)
                            .buttonStyle(.borderedProminent)
                            .padding(20)
                    }
                }
        }
        .navigationSplitViewStyle(.balanced)
        .animation(.easeInOut(duration: 0.25), value: spansFold)
        .onChange(of: path.isEmpty) { _, isEmpty in
            if isEmpty { usesBothHalves = false }
        }
    }

    /// Where a vertical fold runs, measured from the leading edge, for a
    /// page spanning both halves to split itself at.
    ///
    /// The fold counts even while it's inactive (the phone lying flat): the
    /// crease is still there. The split goes on the crease's centre; each
    /// half's margins keep its content clear of the fold.
    private static func foldPosition(in proxy: GeometryProxy) -> CGFloat? {
        guard #available(iOS 27.1, *) else { return nil }
        let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
        guard let fold = folds.first(where: \.isActive) ?? folds.first,
              fold.frame.height > fold.frame.width,
              fold.frame.midX >= 280,
              fold.frame.midX <= proxy.size.width - 280
        else { return nil }
        return fold.frame.midX
    }

    private var pushedOnSelection: Binding<[AppDestination]> {
        Binding {
            Array(path.dropFirst())
        } set: { pushed in
            path = Array(path.prefix(1)) + pushed
        }
    }
}

/// How a list row opens its item when the list is the sidebar of a split.
struct OpenDestinationAction {
    let selected: AppDestination?
    let open: (AppDestination) -> Void
}

extension View {
    /// Keeps content clear of the fold on this side. The crease is about 40
    /// points wide and a page split at its centre, so each side gives half.
    func clearOfFold(_ edges: Edge.Set) -> some View {
        safeAreaPadding(edges, 20)
    }
}

extension EnvironmentValues {
    @Entry var openDestination: OpenDestinationAction?
    /// Set when a page has the whole of an unfolded iPhone Duo: where the
    /// fold runs, in points from the page's leading edge. A page can then
    /// put one part of itself either side of it.
    @Entry var spanningFold: CGFloat?
}

/// A list row that opens a destination: pushes it in a stack, or shows it
/// in the detail column of a split.
struct DestinationLink<Label: View>: View {
    let destination: AppDestination
    /// Whether a pushed row shows the usual chevron. Dense rows such as a
    /// board's leave it out to give the text more room.
    let showsChevron: Bool
    @ViewBuilder let label: () -> Label

    init(_ destination: AppDestination, showsChevron: Bool = true, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.showsChevron = showsChevron
        self.label = label
    }

    @Environment(\.openDestination) private var openDestination

    var body: some View {
        if let openDestination {
            let isSelected = openDestination.selected == destination
            Button {
                openDestination.open(destination)
            } label: {
                HStack {
                    label()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : nil)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else if showsChevron {
            NavigationLink(value: destination, label: label)
        } else {
            // A List draws a chevron on every NavigationLink; a hidden link
            // behind the row keeps the tap without it.
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    NavigationLink(value: destination) { EmptyView() }
                        .opacity(0)
                }
        }
    }
}
