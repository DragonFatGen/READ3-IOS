import LegadoCore
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("阅读 3.0 iOS")
            Text("项目初始化成功")
            Text(LegadoCoreInfo.name)
        }
        .padding()
    }
}
