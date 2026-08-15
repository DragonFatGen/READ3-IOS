import SwiftUI

@main
struct LegadoIOSApp: App {
    @StateObject private var sourceStore: BookSourceStore
    @StateObject private var libraryRepository: LibraryRepository
    private let dependencies: AppDependencies

    init() {
        let dependencies = AppDependencies.live()
        self.dependencies = dependencies
        _sourceStore = StateObject(wrappedValue: dependencies.sourceStore)
        _libraryRepository = StateObject(wrappedValue: dependencies.libraryRepository)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                sourceStore: sourceStore,
                libraryRepository: libraryRepository,
                dependencies: dependencies
            )
        }
    }
}
