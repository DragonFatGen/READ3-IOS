import Foundation
@testable import LegadoCore

struct AlwaysFailingRuntimeTextDecoder: TextDecoder {
    func decode(_ data: Data, charset: String) throws -> String {
        throw HTTPError.decodingFailed(charset)
    }
}
