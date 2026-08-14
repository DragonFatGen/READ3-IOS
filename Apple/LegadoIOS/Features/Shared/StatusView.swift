import Foundation
import SwiftUI

struct StatusView: View {
    let title: String
    let message: String?
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button("重试", action: retry).buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

struct CoverImage: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: urlString.flatMap(URL.init(string:))) { phase in
            switch phase {
            case let .success(image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.secondary.opacity(0.12)
                    Image(systemName: "book.closed").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
