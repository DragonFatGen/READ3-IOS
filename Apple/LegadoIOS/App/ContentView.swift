import SwiftUI

struct ContentView: View {
    @ObservedObject var sourceStore: BookSourceStore
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            SourceListView(sourceStore: sourceStore, dependencies: dependencies)
        }
    }
}
