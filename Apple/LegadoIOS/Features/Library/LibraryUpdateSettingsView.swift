import SwiftUI

struct LibraryUpdateSettingsView: View {
    @ObservedObject var store: LibraryUpdateSettingsStore
    let notifier: any LibraryUpdateNotifying
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("书架更新") {
                Toggle("自动检查更新", isOn: Binding<Bool>(
                    get: { store.settings.automaticCheckEnabled },
                    set: { store.setAutomaticCheckEnabled($0) }
                ))
                Picker("检查频率", selection: Binding<LibraryUpdateInterval>(
                    get: { store.settings.automaticCheckInterval },
                    set: { store.setInterval($0) }
                )) {
                    ForEach(LibraryUpdateInterval.allCases) { interval in
                        Text(interval.title).tag(interval)
                    }
                }
                .disabled(!store.settings.automaticCheckEnabled)
                Toggle("新章节通知", isOn: Binding<Bool>(
                    get: { store.settings.notificationEnabled },
                    set: { enabled in
                        Task { await store.setNotificationEnabled(enabled, notifier: notifier) }
                    }
                ))
                if let message = store.notificationPermissionMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("自动检查只会在 App 处于前台时运行，不会在后台持续联网。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("书架更新")
        .toolbar { Button("完成") { dismiss() } }
        .task { await store.synchronizeNotificationAuthorization(using: notifier) }
    }
}
