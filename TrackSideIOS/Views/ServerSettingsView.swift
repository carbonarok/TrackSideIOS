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

    var body: some View {
        Form {
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
                    HStack {
                        Text("Connect")
                        Spacer()
                        if status == .checking {
                            ProgressView()
                        }
                    }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || status == .checking)
            } footer: {
                switch status {
                case .connected:
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
        }
        .navigationTitle("Server")
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
            status = .failed("The server answered with error \(code). Is this a trackside server?")
            return
        } catch APIError.decodingError {
            status = .failed("That server answered, but not like a trackside server.")
            return
        } catch {
            status = .failed("Couldn't reach the server: \(error.localizedDescription)")
            return
        }
        ServerSettings.save(server)
        status = .connected
        WidgetCenter.shared.reloadAllTimelines()
        onSaved?()
    }
}

#Preview {
    NavigationStack {
        ServerSettingsView()
    }
}
