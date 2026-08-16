import Foundation
import SwiftUI

struct BookSourceManagementView: View {
    @ObservedObject var sourceStore: BookSourceStore
    @ObservedObject var library: LibraryRepository
    @StateObject private var health: SourceHealthCoordinator
    @State private var editingSource: StoredBookSource?
    @State private var deletingSource: StoredBookSource?
    @State private var message: String?

    init(sourceStore: BookSourceStore, dependencies: AppDependencies) {
        self.sourceStore = sourceStore
        library = dependencies.libraryRepository
        _health = StateObject(wrappedValue: SourceHealthCoordinator(service: dependencies.searchService))
    }

    var body: some View {
        List {
            ForEach(groupNames, id: \.self) { groupName in
                Section(groupName.isEmpty ? "未分组" : groupName) {
                    ForEach(sources(in: groupName)) { stored in
                        SourceManagementRow(
                            stored: stored,
                            status: health.status(for: stored.id),
                            onEnabledChanged: { sourceStore.setEnabled($0, for: stored.id) },
                            onTest: { health.test(stored.source) }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { editingSource = stored }
                        .swipeActions {
                            Button("删除", role: .destructive) { requestDelete(stored) }
                            Button("编辑") { editingSource = stored }.tint(.blue)
                        }
                    }
                    .onMove { offsets, target in
                        sourceStore.move(fromOffsets: offsets, toOffset: target, inGroup: groupName)
                    }
                }
            }
        }
        .navigationTitle("书源管理")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("测试全部") { health.testAll(sourceStore.enabledSources) }
                    .disabled(sourceStore.enabledSources.isEmpty)
                EditButton()
            }
        }
        .sheet(item: $editingSource) { source in
            NavigationStack {
                BookSourceEditView(
                    stored: source,
                    sourceStore: sourceStore,
                    library: library,
                    health: health
                ) { requestDelete(source) }
            }
        }
        .confirmationDialog(
            "删除书源？",
            isPresented: Binding(get: { deletingSource != nil }, set: { if !$0 { deletingSource = nil } }),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { confirmDelete() }
            Button("取消", role: .cancel) { deletingSource = nil }
        } message: {
            Text("删除未被书架引用的书源后无法恢复。")
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(message ?? "未知错误") }
        .onDisappear(perform: health.cancelAll)
    }

    private var groupNames: [String] {
        let names = Set(sourceStore.orderedStoredSources.map(\.groupName))
        return names.sorted {
            if $0.isEmpty { return false }
            if $1.isEmpty { return true }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private func sources(in group: String) -> [StoredBookSource] {
        sourceStore.orderedStoredSources.filter { $0.groupName == group }
    }

    private func requestDelete(_ source: StoredBookSource) {
        let count = library.referenceCount(forSourceIdentity: source.id)
        guard count == 0 else {
            message = BookSourceStoreError.sourceIsReferenced(count: count).localizedDescription
            return
        }
        deletingSource = source
    }

    private func confirmDelete() {
        guard let source = deletingSource else { return }
        do {
            try sourceStore.remove(identity: source.id, library: library)
            health.invalidate(identity: source.id)
        } catch { message = error.localizedDescription }
        deletingSource = nil
    }
}

private struct SourceManagementRow: View {
    let stored: StoredBookSource
    let status: SourceHealthStatus
    let onEnabledChanged: (Bool) -> Void
    let onTest: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stored.source.bookSourceName).font(.headline)
                Text(URL(string: stored.source.bookSourceUrl)?.host ?? stored.source.bookSourceUrl)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack {
                    Text(stored.groupName.isEmpty ? "未分组" : stored.groupName)
                    healthLabel
                }
                .font(.caption)
            }
            Spacer()
            Button(action: onTest) { Image(systemName: "stethoscope") }
                .buttonStyle(.borderless).disabled(status == .testing)
            Toggle("启用", isOn: Binding(get: { stored.isEnabled }, set: onEnabledChanged))
                .labelsHidden()
        }
    }

    @ViewBuilder private var healthLabel: some View {
        switch status {
        case .idle: EmptyView()
        case .testing: Label("测试中", systemImage: "hourglass")
        case .available: Label("可用", systemImage: "checkmark.circle").foregroundStyle(.green)
        case let .failed(message):
            Label("失败：\(message)", systemImage: "xmark.circle")
                .foregroundStyle(.red).lineLimit(1)
        }
    }
}

private struct BookSourceEditView: View {
    let stored: StoredBookSource
    @ObservedObject var sourceStore: BookSourceStore
    let library: LibraryRepository
    let health: SourceHealthCoordinator
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var groupName: String
    @State private var isEnabled: Bool
    @State private var jsonText = ""
    @State private var showsJSON = false
    @State private var message: String?

    init(
        stored: StoredBookSource,
        sourceStore: BookSourceStore,
        library: LibraryRepository,
        health: SourceHealthCoordinator,
        onDelete: @escaping () -> Void
    ) {
        self.stored = stored
        self.sourceStore = sourceStore
        self.library = library
        self.health = health
        self.onDelete = onDelete
        _name = State(initialValue: stored.source.bookSourceName)
        _groupName = State(initialValue: stored.groupName)
        _isEnabled = State(initialValue: stored.isEnabled)
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $name)
                TextField("分组", text: $groupName)
                Toggle("启用", isOn: $isEnabled)
                if !sourceStore.groups.isEmpty {
                    Picker("已有分组", selection: $groupName) {
                        Text("未分组").tag("")
                        ForEach(sourceStore.groups, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            Section("高级操作") {
                Button("测试书源") { health.test(stored.source) }
                Button("编辑书源 JSON") { openJSONEditor() }
                Button("删除书源", role: .destructive) { dismiss(); onDelete() }
            }
        }
        .navigationTitle("编辑书源")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    sourceStore.updateMetadata(
                        identity: stored.id, name: name, groupName: groupName, isEnabled: isEnabled
                    )
                    health.invalidate(identity: stored.id)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showsJSON) {
            NavigationStack {
                TextEditor(text: $jsonText).font(.system(.body, design: .monospaced)).padding()
                    .navigationTitle("编辑书源 JSON")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") { showsJSON = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("验证并保存") { saveJSON() }
                        }
                    }
            }
        }
        .alert("无法保存", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(message ?? "未知错误") }
    }

    private func openJSONEditor() {
        do { jsonText = try sourceStore.editableJSON(for: stored.id); showsJSON = true }
        catch { message = error.localizedDescription }
    }

    private func saveJSON() {
        do {
            try sourceStore.replaceFromJSON(jsonText, identity: stored.id, library: library)
            health.invalidate(identity: stored.id)
            showsJSON = false
            dismiss()
        } catch { message = UserFacingError.message(for: error, fallback: "书源 JSON 无效") }
    }
}
