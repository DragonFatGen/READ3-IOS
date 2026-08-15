import SwiftUI

struct ContentView: View {
    @ObservedObject var sourceStore: BookSourceStore
    @ObservedObject var libraryRepository: LibraryRepository
    let dependencies: AppDependencies

    var body: some View {
        TabView {
            NavigationStack {
                BookshelfView(repository: libraryRepository, dependencies: dependencies)
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }

            NavigationStack {
                SourceListView(sourceStore: sourceStore, dependencies: dependencies)
            }
            .tabItem { Label("书源", systemImage: "network") }
        }
    }
}
