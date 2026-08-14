import SwiftUI

@main
struct LegadoIOSApp: App {
    @StateObject private var sourceStore: BookSourceStore
    private let dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _sourceStore = StateObject(wrappedValue: dependencies.sourceStore)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(sourceStore: sourceStore, dependencies: dependencies)
        }
    }
}
