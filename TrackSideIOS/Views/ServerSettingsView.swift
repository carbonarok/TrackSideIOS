import SwiftUI
import WidgetKit

/// Choose the trackside server and its API key. Shown on first launch, and
/// from Settings → Server.
struct ServerSettingsView: View {
    /// Called once a server has been checked and saved.
    var onSaved: (() -> Void)? = nil

    @State private var address = ServerSettings.current?.baseURL.absoluteString ?? ""
    @State private var apiKey = ServerSettings.current?.apiKey ?? ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, checking, connected, failed(String)
    }

    /// The first launch, rather than Settings: welcome them first.
    private var isWelcome: Bool { onSaved != nil }

    var body: some View {
        Form {
            if isWelcome {
                Section {
                    welcome
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("trains.example.com", text: $address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                SecureField("API key, if the server needs one", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { Task { await connect() } }
            } header: {
                Text("Server")
            } footer: {
                Text("TrackSide shows train times from a trackside server. Run your own from github.com/carbonarok/trackside, or use one someone shares with you. Leave the key empty if the server doesn't ask for one.")
            }

            Section {
                Button {
                    Task { await connect() }
                } label: {
                    HStack(spacing: 8) {
                        if status == .checking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(status == .checking ? "Connecting…" : "Connect")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || status == .checking)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                switch status {
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.onTime)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.delaySevere)
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle(isWelcome ? "" : "Server")
        .navigationBarTitleDisplayMode(isWelcome ? .inline : .automatic)
        .sensoryFeedback(trigger: status) { _, new in
            switch new {
            case .connected: .success
            case .failed: .error
            default: nil
            }
        }
        .onChange(of: address) { status = .idle }
        .onChange(of: apiKey) { status = .idle }
    }

    /// Checks the server answers with this key before saving it.
    private func connect() async {
        guard let server = ServerConnection(address: address, apiKey: apiKey) else {
            status = .failed("That doesn't look like a server address.")
            return
        }
        status = .checking
        do {
            _ = try await APIClient(server: server).searchLocations(query: "lon")
        } catch APIError.httpError(let code, _) where code == 401 {
            status = .failed(server.apiKey == nil
                ? "This server needs an API key."
                : "The server didn't accept that API key.")
            return
        } catch APIError.httpError(let code, _) {
            status = .failed(code == 404
                ? "Something answered at that address, but it isn't a trackside server. Check the address, including any path after the name."
                : "The server ran into a problem (error \(code)). Try again in a moment.")
            return
        } catch APIError.decodingError {
            status = .failed("That server answered, but not like a trackside server.")
            return
        } catch {
            status = .failed(error.friendlyDescription)
            return
        }
        ServerSettings.save(server)
        status = .connected
        WidgetCenter.shared.reloadAllTimelines()
        onSaved?()
    }
}

private extension ServerSettingsView {
    var welcome: some View {
        VStack(spacing: 14) {
            Image("AppLogo")
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .accessibilityHidden(true)
            Text("Welcome to TrackSide")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                feature("clock", "Live departures and arrivals for any station")
                feature("arrow.triangle.swap", "Your regular journeys, with every connection worked out")
                feature("location.fill", "Live Activities that follow your train to the platform")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    func feature(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
                .font(.subheadline)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 24)
        }
    }
}

#Preview("Welcome") {
    NavigationStack {
        ServerSettingsView(onSaved: {})
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
