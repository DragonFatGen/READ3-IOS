import SwiftUI

struct ReaderAnnotationsSheet: View {
    let annotations: [ReaderAnnotation]
    let onSelect: (ReaderAnnotation) -> Void
    let onDelete: (UUID) -> Void
    let onUpdate: (UUID, ReaderAnnotationStyle, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var editingAnnotation: ReaderAnnotation?

    var body: some View {
        NavigationStack {
            Group {
                if annotations.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "highlighter").font(.largeTitle)
                        Text("暂无高亮").font(.headline)
                        Text("在正文中选择文字即可添加高亮和批注")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach(annotations) { annotation in
                            annotationRow(annotation)
                                .swipeActions {
                                    Button("删除", role: .destructive) {
                                        onDelete(annotation.id)
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("高亮与批注")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editingAnnotation) { annotation in
                ReaderAnnotationEditSheet(annotation: annotation) { style, note in
                    onUpdate(annotation.id, style, note)
                    editingAnnotation = nil
                }
            }
        }
    }

    private func annotationRow(_ annotation: ReaderAnnotation) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onSelect(annotation)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle().fill(annotation.style.color).frame(width: 12, height: 12)
                        Text(annotation.chapterName).font(.headline).lineLimit(1)
                    }
                    Text(annotation.selectedText).foregroundStyle(.primary).lineLimit(3)
                    if let note = annotation.note {
                        Label(note, systemImage: "note.text")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Text(annotation.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button {
                editingAnnotation = annotation
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("编辑批注")
        }
    }
}

struct ReaderAnnotationComposerSheet: View {
    let selection: ReaderTextSelection
    let onSave: (ReaderAnnotationStyle, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var style: ReaderAnnotationStyle = .yellow
    @State private var note = ""

    var body: some View {
        NavigationStack {
            annotationForm(selectedText: selection.selectedText, style: $style, note: $note)
                .navigationTitle("添加高亮")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            onSave(style, note)
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct ReaderAnnotationEditSheet: View {
    let annotation: ReaderAnnotation
    let onSave: (ReaderAnnotationStyle, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var style: ReaderAnnotationStyle
    @State private var note: String

    init(
        annotation: ReaderAnnotation,
        onSave: @escaping (ReaderAnnotationStyle, String?) -> Void
    ) {
        self.annotation = annotation
        self.onSave = onSave
        _style = State(initialValue: annotation.style)
        _note = State(initialValue: annotation.note ?? "")
    }

    var body: some View {
        NavigationStack {
            annotationForm(selectedText: annotation.selectedText, style: $style, note: $note)
                .navigationTitle("编辑批注")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            onSave(style, note)
                            dismiss()
                        }
                    }
                }
        }
    }
}

private func annotationForm(
    selectedText: String,
    style: Binding<ReaderAnnotationStyle>,
    note: Binding<String>
) -> some View {
    Form {
        Section("选中文字") {
            Text(selectedText).textSelection(.enabled)
        }
        Section("高亮样式") {
            Picker("高亮样式", selection: style) {
                ForEach(ReaderAnnotationStyle.allCases, id: \.self) { value in
                    Label {
                        Text(value.title)
                    } icon: {
                        Circle().fill(value.color)
                    }
                    .tag(value)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Section("文字批注") {
            TextEditor(text: note).frame(minHeight: 100)
        }
    }
}
