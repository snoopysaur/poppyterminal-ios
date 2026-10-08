import SwiftUI
import PoppyKit

/// Editor dos snippets da barra do terminal: adicionar, editar, reordenar, apagar, restaurar.
struct SnippetsView: View {
    @State private var snippets = SnippetStorage.load()
    @State private var editing: Snippet?
    @State private var confirmRestore = false

    var body: some View {
        List {
            Section {
                ForEach(snippets) { snippet in
                    Button { editing = snippet } label: { row(snippet) }
                        .buttonStyle(.plain)
                        .listRowBackground(Theme.Palette.surface)
                }
                .onDelete { snippets.remove(atOffsets: $0) }
                .onMove { snippets.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                Text("Um toque no terminal envia o texto")
            } footer: {
                Text("\(snippets.count) de \(SnippetList.maxCount). Arraste para reordenar, deslize para apagar.")
            }
            Section {
                Button("Restaurar padrões", role: .destructive) { confirmRestore = true }
                    .listRowBackground(Theme.Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Palette.base)
        .navigationTitle("Snippets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !snippets.isEmpty { EditButton() }
                Button {
                    editing = Snippet(title: "", text: "")
                } label: {
                    Label("Novo snippet", systemImage: "plus")
                }
                .disabled(snippets.count >= SnippetList.maxCount)
            }
        }
        .sheet(item: $editing) { draft in
            SnippetEditSheet(draft: draft) { saved in
                if let i = snippets.firstIndex(where: { $0.id == saved.id }) {
                    snippets[i] = saved
                } else {
                    snippets.append(saved)
                }
            }
        }
        .confirmationDialog("Restaurar os snippets padrão?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restaurar padrões", role: .destructive) { snippets = SnippetList.defaults }
        } message: {
            Text("Seus snippets atuais serão substituídos.")
        }
        .onChange(of: snippets) { _, new in SnippetStorage.save(new) }
    }

    private func row(_ s: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(s.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.text)
            Text(s.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                .font(.custom(Theme.fontRegular, size: 13, relativeTo: .footnote))
                .foregroundStyle(Theme.Palette.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SnippetEditSheet: View {
    @State var draft: Snippet
    var onSave: (Snippet) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Título") {
                    TextField("claude", text: $draft.title)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .listRowBackground(Theme.Palette.surface)
                }
                Section {
                    TextField("Texto enviado", text: $draft.text, axis: .vertical)
                        .font(.custom(Theme.fontRegular, size: 15, relativeTo: .body))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(2...6)
                        .listRowBackground(Theme.Palette.surface)
                    Toggle("Enviar Enter no final", isOn: $draft.appendsReturn)
                        .listRowBackground(Theme.Palette.surface)
                } header: {
                    Text("Comando")
                } footer: {
                    Text("Até \(SnippetList.maxTextLength) caracteres.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.base)
            .navigationTitle("Snippet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!draft.isSendable)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
