import SwiftUI

@main
struct LegadoIOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
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
            .task {
                if scenePhase == .active {
                    dependencies.libraryAutoUpdateCoordinator.applicationDidBecomeActive()
                }
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active {
                    dependencies.libraryAutoUpdateCoordinator.applicationDidBecomeActive()
                } else {
                    dependencies.libraryAutoUpdateCoordinator.applicationDidLeaveActiveState()
                }
            }
        }
    }
}
