import SwiftUI
import SwiftData

struct DepartureBoardView: View {
    let liveClient: LiveClient

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FavouriteStation.addedAt, order: .reverse) private var favourites: [FavouriteStation]
    @State private var boardService: DepartureBoardService
    @State private var showingSearch = false
    @State private var selectedStation: Location?
    @State private var searchMode: SearchMode = .station
    @State private var serviceQuery = ""
    @State private var serviceResults: [ServiceSummary] = []
    @State private var isSearchingServices = false
    @AppStorage("lastStationCode") private var lastStationCode = ""
    @AppStorage("lastStationName") private var lastStationName = ""
    @State private var callingAtFilter = ""
    @State private var showCallingAtSearch = false
    @State private var showMessages = false
    @FocusState private var callingAtFocused: Bool

    private let apiClient = APIClient()

    enum SearchMode {
        case station
        case service
    }

    init(liveClient: LiveClient) {
        self.liveClient = liveClient
        self._boardService = State(initialValue: DepartureBoardService(liveClient: liveClient))
    }

    var body: some View {
        Group {
            if let board = boardService.board {
                boardContent(board)
            } else if boardService.isLoading {
                ProgressView("Loading \(boardService.mode.rawValue.lowercased())...")
            } else if let error = boardService.error {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    if selectedStation != nil {
                        Button("Retry") {
                            Task { await reload() }
                        }
                    }
                }
            } else {
                // No station selected — show favourites or prompt
                noStationView
            }
        }
        // Pinned above whatever the board shows, even no station yet.
        .safeAreaInset(edge: .top) {
            TrackedJourneyBanner()
        }
        .navigationTitle(selectedStation?.name ?? "Departures")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            .keepsVisible(.high)
            if selectedStation != nil {
                ToolbarItem(placement: .primaryAction) {
                    filterButton
                }
                ToolbarItem(placement: .topBarLeading) {
                    favouriteButton
                }
                .keepsVisible(.low)
            }
        }
        // Finding a train by headcode, in the standard search bar rather
        // than a row above the board.
        // Always a field under the title: as a toolbar button (iOS 27 does
        // that in narrower columns) it sat next to the station search button
        // with the same magnifying glass.
        .searchable(
            text: $serviceQuery,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Find a train by headcode"
        )
        .textInputAutocapitalization(.characters)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            searchServices()
        }
        .onChange(of: serviceQuery) { _, newValue in
            if newValue.count >= 3 {
                searchServices()
            } else if newValue.isEmpty {
                serviceResults = []
            }
        }
        .sheet(isPresented: $showingSearch) {
            StationSearchView { location in
                selectStation(location)
            }
        }
        .refreshable {
            await reload()
        }
        .task {
            if selectedStation == nil && !lastStationCode.isEmpty {
                selectedStation = Location(tiploc: lastStationCode, crs: lastStationCode.count == 3 ? lastStationCode : nil, name: lastStationName)
                await boardService.loadBoard(for: lastStationCode)
            }
        }
        .onDisappear {
            boardService.stopLive()
        }
    }

    // MARK: - No Station View (Favourites + Search)

    @ViewBuilder
    private var noStationView: some View {
        if favourites.isEmpty && serviceResults.isEmpty {
            ContentUnavailableView {
                Label("No Station Selected", systemImage: "train.side.front.car")
            } description: {
                Text("Tap the search button to find a station")
            } actions: {
                Button("Search Stations") {
                    showingSearch = true
                }
            }
        } else {
            List {
                if isSearchingServices && serviceResults.isEmpty {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !serviceResults.isEmpty {
                    Section {
                        ForEach(serviceResults, id: \.id) { service in
                            DestinationLink(.service(ServiceRoute(uid: service.uid, runDate: service.runDate))) {
                                serviceResultRow(service)
                            }
                        }
                    } header: {
                        Text("\(serviceResults.count) services found")
                    }
                }

                // Favourites
                Section {
                    ForEach(favourites) { station in
                        Button {
                            let location = Location(tiploc: station.code, crs: station.code.count == 3 ? station.code : nil, name: station.name)
                            selectStation(location)
                        } label: {
                            HStack(spacing: 12) {
                                // Station icon with accent
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(.blue.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "train.side.front.car")
                                        .font(.body)
                                        .foregroundStyle(.blue)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(station.code)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(.secondary.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 3))
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 8))
                                            .foregroundStyle(.yellow)
                                    }
                                    .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            modelContext.delete(favourites[index])
                        }
                    }
                } header: {
                    Text("Favourite Stations")
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Board Content

    @ViewBuilder
    private func boardContent(_ board: Board) -> some View {
        List {
            // Mode picker
            Section {
                Picker("Board Type", selection: $boardService.mode) {
                    ForEach(BoardMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            // Cached data banner
            if boardService.isCachedData {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Showing cached data")
                                .font(.caption)
                                .fontWeight(.medium)
                            Text("Pull to refresh for live times")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if boardService.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if isSearchingServices && serviceResults.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !serviceResults.isEmpty {
                Section {
                    ForEach(serviceResults, id: \.id) { service in
                        DestinationLink(.service(ServiceRoute(uid: service.uid, runDate: service.runDate))) {
                            serviceResultRow(service)
                        }
                    }
                } header: {
                    Text("\(serviceResults.count) services found")
                }
            }

            // Calling at filter, opened from the toolbar
            if showCallingAtSearch {
                Section {
                    HStack {
                        Image(systemName: "line.3.horizontal.decrease")
                            .foregroundStyle(.tint)
                        TextField("Calling at station code (e.g. RDG)", text: $callingAtFilter)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .focused($callingAtFocused)
                        if !callingAtFilter.isEmpty {
                            Button {
                                callingAtFilter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Clear filter")
                        }
                    }
                }
            }

            // Station messages, folded into one line until opened
            if !board.messages.isEmpty {
                Section {
                    messagesSummary(board.messages)
                    if showMessages {
                        ForEach(board.messages) { message in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: messageSeverityIcon(message.severity))
                                    .foregroundStyle(messageSeverityColor(message.severity))
                                    .padding(.top, 2)
                                Text(message.text)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Services
            Section {
                let filtered = filteredServices(board.services)
                ForEach(filtered) { service in
                    DestinationLink(.service(ServiceRoute(uid: service.uid, runDate: service.runDate)), showsChevron: false) {
                        BoardServiceRow(service: service)
                    }
                }
            } header: {
                let filtered = filteredServices(board.services)
                if !callingAtFilter.isEmpty {
                    Text("\(filtered.count) of \(board.services.count) \(boardService.mode.rawValue.lowercased()) calling at \(callingAtFilter.uppercased())")
                } else {
                    Text("\(board.services.count) \(boardService.mode.rawValue.lowercased())")
                }
            }
        }
        .listStyle(.plain)
        .onChange(of: boardService.mode) { _, newMode in
            guard let code = selectedStation?.displayCode else { return }
            Task { await boardService.loadBoard(for: code, mode: newMode) }
        }
    }

    // MARK: - Station Messages

    /// One line for all of a station's messages: the most serious one's
    /// icon, how many there are, and the start of the most serious.
    private func messagesSummary(_ messages: [StationMessage]) -> some View {
        let worst = messages.max { $0.severity < $1.severity }!
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { showMessages.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: messageSeverityIcon(worst.severity))
                    .foregroundStyle(messageSeverityColor(worst.severity))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(messages.count == 1 ? "1 station message" : "\(messages.count) station messages")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if !showMessages {
                        Text(worst.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showMessages ? 180 : 0))
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(showMessages ? "Hides the messages" : "Shows the messages")
    }

    // MARK: - Calling Point Filter

    private var filterButton: some View {
        let active = showCallingAtSearch || !callingAtFilter.isEmpty
        return Button {
            withAnimation {
                if active {
                    showCallingAtSearch = false
                    callingAtFilter = ""
                } else {
                    showCallingAtSearch = true
                    callingAtFocused = true
                }
            }
        } label: {
            Label(
                active ? "Stop filtering" : "Filter by calling point",
                systemImage: active ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
        }
    }

    @ViewBuilder
    private func serviceResultRow(_ service: ServiceSummary) -> some View {
        HStack(spacing: 10) {
            if let op = service.operator {
                RoundedRectangle(cornerRadius: 2)
                    .fill(op.brandColor)
                    .frame(width: 4, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let headcode = service.headcode {
                        Text(headcode)
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .monospaced()
                    }
                    StatusBadge(status: service.status, cancelled: service.isCancelled)
                }
                HStack(spacing: 4) {
                    Text(service.originName)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(service.destinationName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let op = service.operator {
                    Text(op.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Favourite Button

    @ViewBuilder
    private var favouriteButton: some View {
        if let station = selectedStation {
            let isFavourite = favourites.contains { $0.code == station.displayCode }
            Button {
                if isFavourite {
                    if let existing = favourites.first(where: { $0.code == station.displayCode }) {
                        modelContext.delete(existing)
                    }
                } else {
                    let fav = FavouriteStation(code: station.displayCode, name: station.name)
                    modelContext.insert(fav)
                }
            } label: {
                // A title as well as the star: where toolbars run short of
                // room (the iPhone Duo's vertical bars), the item moves to an
                // overflow menu that shows the title.
                Label(isFavourite ? "Remove from Favourites" : "Add to Favourites",
                      systemImage: isFavourite ? "star.fill" : "star")
                    .foregroundStyle(isFavourite ? .yellow : .secondary)
            }
        }
    }

    // MARK: - Helpers

    private func selectStation(_ location: Location) {
        selectedStation = location
        lastStationCode = location.displayCode
        lastStationName = location.name
        serviceResults = []
        serviceQuery = ""
        Task { await boardService.loadBoard(for: location.displayCode, mode: boardService.mode) }
    }

    private func searchServices() {
        let query = serviceQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return }
        isSearchingServices = true
        Task {
            do {
                serviceResults = try await apiClient.searchServices(query: query)
            } catch {
                serviceResults = []
            }
            isSearchingServices = false
        }
    }

    private func reload() async {
        guard let code = selectedStation?.displayCode ?? (lastStationCode.isEmpty ? nil : lastStationCode) else { return }
        await boardService.loadBoard(for: code, mode: boardService.mode)
    }

    /// Filter services by calling point — checks if any destination matches the filter code
    private func filteredServices(_ services: [BoardService]) -> [BoardService] {
        let code = callingAtFilter.trimmingCharacters(in: .whitespaces).uppercased()
        guard !code.isEmpty else { return services }
        return services.filter { service in
            service.destination.contains { dest in
                dest.crs?.uppercased() == code || dest.tiploc.uppercased() == code || dest.name.localizedCaseInsensitiveContains(code)
            }
        }
    }

    private func messageSeverityIcon(_ severity: Int) -> String {
        switch severity {
        case 3: return "exclamationmark.octagon.fill"
        case 2: return "exclamationmark.triangle.fill"
        case 1: return "info.circle.fill"
        default: return "info.circle"
        }
    }

    private func messageSeverityColor(_ severity: Int) -> Color {
        switch severity {
        case 3: return .red
        case 2: return .orange
        case 1: return .yellow
        default: return .blue
        }
    }
}
