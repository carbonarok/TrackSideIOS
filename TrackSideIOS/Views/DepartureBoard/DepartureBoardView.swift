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
        .navigationTitle(selectedStation?.name ?? "Departures")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSearch = true
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
            }
            if selectedStation != nil {
                ToolbarItem(placement: .topBarLeading) {
                    favouriteButton
                }
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
        if favourites.isEmpty {
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
                // Service search
                Section {
                    serviceSearchBar
                } header: {
                    Text("Search by Headcode")
                }

                if !serviceResults.isEmpty {
                    Section {
                        ForEach(serviceResults, id: \.id) { service in
                            NavigationLink(value: service) {
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
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    Text(station.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
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
            .navigationDestination(for: ServiceSummary.self) { service in
                ServiceDetailView(uid: service.uid, runDate: service.runDate, liveClient: liveClient)
            }
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
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            // Service search
            Section {
                serviceSearchBar
            }

            if !serviceResults.isEmpty {
                Section {
                    ForEach(serviceResults, id: \.id) { service in
                        NavigationLink(value: service) {
                            serviceResultRow(service)
                        }
                    }
                } header: {
                    Text("\(serviceResults.count) services found")
                }
            }

            // Station messages
            if !board.messages.isEmpty {
                Section {
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
                } header: {
                    Label("Station Messages", systemImage: "exclamationmark.bubble")
                }
            }

            // Services
            Section {
                ForEach(board.services) { service in
                    NavigationLink(value: service) {
                        BoardServiceRow(service: service)
                    }
                }
            } header: {
                Text("\(board.services.count) \(boardService.mode.rawValue.lowercased())")
            }
        }
        .listStyle(.plain)
        .navigationDestination(for: BoardService.self) { service in
            ServiceDetailView(
                uid: service.uid,
                runDate: service.runDate,
                liveClient: liveClient
            )
        }
        .navigationDestination(for: ServiceSummary.self) { service in
            ServiceDetailView(uid: service.uid, runDate: service.runDate, liveClient: liveClient)
        }
        .onChange(of: boardService.mode) { _, newMode in
            guard let code = selectedStation?.displayCode else { return }
            Task { await boardService.loadBoard(for: code, mode: newMode) }
        }
    }

    // MARK: - Service Search

    @ViewBuilder
    private var serviceSearchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search headcode (e.g. 1C45)", text: $serviceQuery)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit {
                    searchServices()
                }
            if !serviceQuery.isEmpty {
                Button {
                    serviceQuery = ""
                    serviceResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            if isSearchingServices {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .onChange(of: serviceQuery) { _, newValue in
            if newValue.count >= 3 {
                searchServices()
            } else if newValue.isEmpty {
                serviceResults = []
            }
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
                Image(systemName: isFavourite ? "star.fill" : "star")
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
