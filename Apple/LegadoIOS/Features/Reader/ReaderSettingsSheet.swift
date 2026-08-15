import SwiftUI

struct ReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ReaderSettingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读模式") {
                    HStack {
                        ForEach(ReaderLayoutMode.allCases, id: \.self) { mode in
                            Button {
                                store.selectLayoutMode(mode)
                            } label: {
                                Text(mode.title)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(Color.accentColor.opacity(
                                store.settings.layoutMode == mode ? 1 : 0.55
                            ))
                            .accessibilityValue(
                                store.settings.layoutMode == mode ? "已选择" : ""
                            )
                        }
                    }
                }
                stepperRow(
                    title: "字号",
                    value: store.settings.fontSize,
                    decreaseLabel: "减小字号",
                    increaseLabel: "增加字号",
                    decrease: { store.adjustFontSize(by: -1) },
                    increase: { store.adjustFontSize(by: 1) }
                )
                stepperRow(
                    title: "行距",
                    value: store.settings.lineSpacing,
                    decreaseLabel: "减小行距",
                    increaseLabel: "增加行距",
                    decrease: { store.adjustLineSpacing(by: -1) },
                    increase: { store.adjustLineSpacing(by: 1) }
                )
                stepperRow(
                    title: "左右边距",
                    value: store.settings.horizontalPadding,
                    decreaseLabel: "减小左右边距",
                    increaseLabel: "增加左右边距",
                    decrease: { store.adjustHorizontalPadding(by: -2) },
                    increase: { store.adjustHorizontalPadding(by: 2) }
                )
                Section("主题") {
                    Picker(
                        "主题",
                        selection: Binding<ReaderTheme>(
                            get: { store.settings.theme },
                            set: { theme in
                                store.selectTheme(theme)
                            }
                        )
                    ) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("阅读设置")
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func stepperRow(
        title: String,
        value: Double,
        decreaseLabel: String,
        increaseLabel: String,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: decrease) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(decreaseLabel)
            Text(value, format: .number.precision(.fractionLength(0)))
                .monospacedDigit().frame(minWidth: 30)
            Button(action: increase) { Image(systemName: "plus.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel(increaseLabel)
        }
    }
}
