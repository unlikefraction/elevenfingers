import SwiftUI

struct DictionaryEditorView: View {
    @State private var text: String = DictionaryStore.shared.get()
    @State private var saved: Bool = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Your personal writing ruleset, appended to every OCR/STT/Writer call.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()

                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemBackground))

                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                }
            }
            .navigationTitle("Dictionary")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        DictionaryStore.shared.set(text)
                        withAnimation { saved = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { saved = false }
                        }
                    }
                }
            }
        }
    }
}
