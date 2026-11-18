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
    @State private var columnVisibility = NavigationSplitViewVisibility.all

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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar()
                .environment(\.openDestination, OpenDestinationAction(selected: path.first) { path = [$0] })
                .navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        } detail: {
            // The selected item is the root of the detail column, so it has
            // no back button. Anything it opens is pushed on top.
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
                .navigationDestination(for: AppDestination.self, destination: destination)
            }
        }
        .navigationSplitViewStyle(.balanced)
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

extension EnvironmentValues {
    @Entry var openDestination: OpenDestinationAction?
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
