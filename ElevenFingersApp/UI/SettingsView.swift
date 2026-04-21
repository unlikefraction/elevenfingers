import SwiftUI

struct SettingsView: View {
    @State private var backendURL: String = AppGroup.userDefaults.string(forKey: DefaultsKeys.backendURL) ?? BackendConfig.defaultURL
    @State private var languageCode: String = AppGroup.userDefaults.string(forKey: DefaultsKeys.languageCode) ?? "eng"
    @State private var sessionDuration: SessionDurationOption = {
        let raw = AppGroup.userDefaults.string(forKey: DefaultsKeys.sessionDuration) ?? SessionDurationOption.untilStopped.rawValue
        return SessionDurationOption(rawValue: raw) ?? .untilStopped
    }()
    @State private var healthMessage: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Base URL", text: $backendURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("Test connection") {
                        Task { await testHealth() }
                    }
                    if !healthMessage.isEmpty {
                        Text(healthMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Section("Session") {
                    Picker("Duration", selection: $sessionDuration) {
                        ForEach(SessionDurationOption.allCases, id: \.self) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section("Language") {
                    TextField("Scribe language code", text: $languageCode)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        AppGroup.userDefaults.set(backendURL, forKey: DefaultsKeys.backendURL)
        AppGroup.userDefaults.set(languageCode, forKey: DefaultsKeys.languageCode)
        AppGroup.userDefaults.set(sessionDuration.rawValue, forKey: DefaultsKeys.sessionDuration)
    }

    private func testHealth() async {
        save()
        let url = BackendConfig.baseURL().appendingPathComponent("health")
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                healthMessage = "OK — \(String(data: data, encoding: .utf8) ?? "")"
            } else {
                healthMessage = "Unexpected response"
            }
        } catch {
            healthMessage = "Error: \(error.localizedDescription)"
        }
    }
}
