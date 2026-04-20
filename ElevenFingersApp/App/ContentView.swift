import SwiftUI

struct ContentView: View {
    @StateObject private var flow = FlowSessionController.shared
    @StateObject private var pipeline = PipelineCoordinator.shared

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            DictionaryEditorView()
                .tabItem { Label("Dictionary", systemImage: "text.book.closed") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }

            DebugLogView()
                .tabItem { Label("Debug", systemImage: "ladybug") }
        }
        .tint(.accentColor)
        .environmentObject(flow)
        .environmentObject(pipeline)
    }
}

struct HomeView: View {
    @EnvironmentObject var flow: FlowSessionController
    @EnvironmentObject var pipeline: PipelineCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SessionCard()
                    LastResultCard()
                    KeyboardShortcutCard()
                }
                .padding()
            }
            .navigationTitle("ElevenFingers")
            .background(Color(.systemGroupedBackground))
        }
    }
}

struct SessionCard: View {
    @EnvironmentObject var flow: FlowSessionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Flow Session")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(flow.isActive ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
            }

            Text(flow.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if flow.isActive {
                    Button(role: .destructive) { flow.stop() } label: {
                        Label("Stop Session", systemImage: "stop.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { flow.start() } label: {
                        Label("Start Session", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LastResultCard: View {
    @EnvironmentObject var pipeline: PipelineCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last Result")
                .font(.headline)
            if pipeline.lastResult.isEmpty {
                Text("No result yet. Submit from the keyboard once it's active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text(pipeline.lastResult)
                    .font(.body)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeyboardShortcutCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Getting Started")
                .font(.headline)
            Text("1. Allow microphone when prompted.\n2. In Settings → General → Keyboard → Keyboards, add ElevenFingers and enable Full Access.\n3. Start a Flow Session and bring up the keyboard in any app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Keyboard Settings", systemImage: "keyboard")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
