import SwiftUI

/// Text-based meal entry. The athlete types ("two eggs, oatmeal with banana")
/// and Sonnet parses → we surface the result in the existing PhotoConfirmView
/// (renamed conceptually as ConfirmView; reused for both photo + text).
struct TextEntryView: View {
    let mealType: String
    var onParsed: (ParsedMealDTO) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var isParsing = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Describe what you ate. Be specific with portions where you can.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("e.g. two eggs, oatmeal with banana, coffee", text: $text, axis: .vertical)
                    .lineLimit(3...8)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)

                if let err = error {
                    Text(err).font(.callout).foregroundStyle(.red)
                }

                Button {
                    Task { await parse() }
                } label: {
                    if isParsing {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        Text("Parse")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(Color.stridePrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsing)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .navigationTitle("Text entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        }
    }

    private func parse() async {
        isParsing = true
        defer { isParsing = false }
        do {
            let parsed = try await APIService.shared.parseMealText(description: text, mealType: mealType)
            onParsed(parsed)
        } catch {
            self.error = "Couldn't parse — try simplifying."
        }
    }
}
