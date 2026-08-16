import Foundation
import SwiftUI

struct BookSourceManagementView: View {
    @ObservedObject var sourceStore: BookSourceStore
    @ObservedObject var library: LibraryRepository
    @StateObject private var health: SourceHealthCoordinator
    @State private var editingSource: StoredBookSource?
    @State private var deletingIdentities: Set<String> = []
    @State private var selectedIdentities: Set<String> = []
    @State private var isSelecting = false
    @State private var message: String?

    init(sourceStore: BookSourceStore, dependencies: AppDependencies) {
        self.sourceStore = sourceStore
        library = dependencies.libraryRepository
        _health = StateObject(wrappedValue: SourceHealthCoordinator(service: dependencies.searchService))
    }

    var body: some View {
        List {
            if sourceStore.storedSources.isEmpty {
                Section {
                    StatusView(title: "暂无书源", message: "请返回书源页导入书源")
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(groupNames, id: \.self) { groupName in
                Section(groupName.isEmpty ? "未分组" : groupName) {
                    ForEach(sources(in: groupName)) { stored in
                        HStack(spacing: 10) {
                            if isSelecting {
                                if selectedIdentities.contains(stored.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(.secondary)
                                }
                            }
                            SourceManagementRow(
                                stored: stored,
                                status: health.status(for: stored.id),
                                onEnabledChanged: { sourceStore.setEnabled($0, for: stored.id) },
                                onTest: { health.test(stored.source) }
                            )
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting { toggleSelection(stored.id) }
                            else { editingSource = stored }
                        }
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
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button(selectedIdentities.count == sourceStore.storedSources.count ? "取消全选" : "全选") {
                        if selectedIdentities.count == sourceStore.storedSources.count {
                            selectedIdentities.removeAll()
                        } else {
                            selectedIdentities = Set(sourceStore.storedSources.map(\.id))
                        }
                    }
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Menu {
                        Button("批量启用") { setSelectedEnabled(true) }
                        Button("批量禁用") { setSelectedEnabled(false) }
                        Button("批量删除", role: .destructive) {
                            deletingIdentities = selectedIdentities
                        }
                    } label: { Label("批量操作", systemImage: "ellipsis.circle") }
                    .disabled(selectedIdentities.isEmpty)
                    Button("完成") { endSelection() }
                } else {
                    Button("测试全部") { health.testAll(sourceStore.enabledSources) }
                        .disabled(sourceStore.enabledSources.isEmpty)
                    Button("选择") { isSelecting = true }
                    EditButton()
                }
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
            isPresented: Binding(
                get: { !deletingIdentities.isEmpty },
                set: { if !$0 { deletingIdentities.removeAll() } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { confirmDelete() }
            Button("取消", role: .cancel) { deletingIdentities.removeAll() }
        } message: {
            let count = sourceStore.referenceCount(for: deletingIdentities, library: library)
            if count > 0 {
                Text("选中的书源仍被书架中的 \(count) 本书使用。删除后书籍、进度、书签和缓存会保留，但无法检查更新。")
            } else {
                Text("将删除选中的 \(deletingIdentities.count) 个书源，此操作无法恢复。")
            }
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
        deletingIdentities = [source.id]
    }

    private func confirmDelete() {
        let identities = deletingIdentities
        do {
            try sourceStore.remove(
                identities: identities,
                library: library,
                allowingReferences: true
            )
            identities.forEach { health.invalidate(identity: $0) }
            selectedIdentities.subtract(identities)
        } catch { message = error.localizedDescription }
        deletingIdentities.removeAll()
    }

    private func toggleSelection(_ identity: String) {
        if selectedIdentities.contains(identity) { selectedIdentities.remove(identity) }
        else { selectedIdentities.insert(identity) }
    }

    private func setSelectedEnabled(_ enabled: Bool) {
        sourceStore.setEnabled(enabled, for: selectedIdentities)
    }

    private func endSelection() {
        isSelecting = false
        selectedIdentities.removeAll()
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
