import SwiftUI

struct DebugLogView: View {
    @EnvironmentObject var pipeline: PipelineCoordinator

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pipeline.logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onChange(of: pipeline.logs.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .navigationTitle("Debug")
        }
    }
}
