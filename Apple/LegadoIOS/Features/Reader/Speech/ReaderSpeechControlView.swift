import Foundation
import SwiftUI

struct ReaderSpeechControlView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var controller: ReaderSpeechController
    @ObservedObject var settingsStore: ReaderSpeechSettingsStore
    let reader: ReaderViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("朗读控制") {
                    HStack {
                        speechButton("上一句", icon: "backward.end.fill", action: controller.previousSegment)
                        Spacer()
                        Button {
                            controller.togglePlayback(from: reader)
                        } label: {
                            Label(primaryTitle, systemImage: primaryIcon)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityLabel(primaryTitle)
                        Spacer()
                        speechButton("下一句", icon: "forward.end.fill", action: controller.nextSegment)
                        Spacer()
                        speechButton("停止朗读", icon: "stop.fill", action: controller.stop)
                    }
                    if let message = controller.speechErrorMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                }

                Section("语速") {
                    Picker(
                        "语速",
                        selection: Binding<Double>(
                            get: { settingsStore.settings.rate },
                            set: controller.selectRate
                        )
                    ) {
                        ForEach(ReaderSpeechSettings.supportedRates, id: \.self) { rate in
                            Text(String(format: "%.1fx", rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("睡眠定时") {
                    Picker(
                        "停止时间",
                        selection: Binding<ReaderSleepTimerOption>(
                            get: { controller.sleepTimerOption },
                            set: controller.selectSleepTimer
                        )
                    ) {
                        ForEach(ReaderSleepTimerOption.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                Section("朗读设置") {
                    Toggle(
                        "连续朗读下一章",
                        isOn: Binding<Bool>(
                            get: { settingsStore.settings.continuousReading },
                            set: controller.selectContinuousReading
                        )
                    )
                    NavigationLink("系统语音") {
                        ReaderSpeechSettingsView(
                            controller: controller,
                            settingsStore: settingsStore
                        )
                    }
                }
            }
            .navigationTitle("朗读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private var primaryTitle: String {
        switch controller.state {
        case .speaking, .preparing: "暂停朗读"
        case .paused: "继续朗读"
        case .idle: "开始朗读"
        }
    }

    private var primaryIcon: String {
        switch controller.state {
        case .speaking, .preparing: "pause.fill"
        case .paused, .idle: "play.fill"
        }
    }

    private func speechButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { Label(title, systemImage: icon).labelStyle(.iconOnly) }
            .accessibilityLabel(title)
            .disabled(controller.state == .idle)
    }
}

struct ReaderSpeechSettingsView: View {
    @ObservedObject var controller: ReaderSpeechController
    @ObservedObject var settingsStore: ReaderSpeechSettingsStore

    var body: some View {
        List {
            Section("默认语音") {
                Button {
                    controller.selectVoice(identifier: nil)
                } label: {
                    voiceRow(title: "中文系统默认", selected: settingsStore.settings.voiceIdentifier == nil)
                }
            }
            if !chineseVoices.isEmpty {
                Section("中文") {
                    voiceButtons(chineseVoices)
                }
            }
            if !otherVoices.isEmpty {
                Section("其他语言") {
                    voiceButtons(otherVoices)
                }
            }
        }
        .navigationTitle("系统语音")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chineseVoices: [ReaderSpeechVoice] {
        controller.availableVoices.filter(\.isChinese)
    }

    private var otherVoices: [ReaderSpeechVoice] {
        controller.availableVoices.filter { !$0.isChinese }
    }

    @ViewBuilder
    private func voiceButtons(_ voices: [ReaderSpeechVoice]) -> some View {
        ForEach(voices) { voice in
            Button {
                controller.selectVoice(identifier: voice.id)
            } label: {
                voiceRow(
                    title: "\(voice.name)（\(voice.language)）",
                    selected: settingsStore.settings.voiceIdentifier == voice.id
                )
            }
        }
    }

    private func voiceRow(title: String, selected: Bool) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            if selected { Image(systemName: "checkmark").accessibilityLabel("已选择") }
        }
    }
}
