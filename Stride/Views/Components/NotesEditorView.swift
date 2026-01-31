import SwiftUI

/// View for adding/editing workout notes
struct NotesEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var notes: String?
    @State private var editedNotes: String
    @FocusState private var isTextFieldFocused: Bool
    
    
    
    init(notes: Binding<String?>) {
        self._notes = notes
        self._editedNotes = State(initialValue: notes.wrappedValue ?? "")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $editedNotes)
                    .focused($isTextFieldFocused)
                    .font(.system(size: 16, weight: .regular))
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemBackground))
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        if editedNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            notes = nil
                        } else {
                            notes = editedNotes
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.stridePrimary)
                }
            }
            .onAppear {
                isTextFieldFocused = true
            }
        }
    }
}



