import Foundation
import LegadoCore

@main
enum LegadoCompatibilityMain {
    static func main() async {
        let httpClient = CookieSessionHTTPClient(
            transport: URLSessionHTTPClient(),
            cookieStore: InMemoryHTTPCookieStore()
        )
        let execution = await CompatibilityCLIApplication().run(
            arguments: Array(CommandLine.arguments.dropFirst()),
            httpClient: httpClient
        )
        FileHandle.standardOutput.write(Data((execution.output + "\n").utf8))
        if execution.exitCode != .success {
            exit(execution.exitCode.rawValue)
        }
    }
}
