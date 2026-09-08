import Foundation
import LegadoCore

enum CLIExitCode: Int32, Equatable {
    case success = 0
    case compatibilityFailure = 1
    case inputError = 2
}

struct CLIExecution: Equatable {
    let exitCode: CLIExitCode
    let output: String
}

struct CompatibilityCLIApplication {
    private let parser = CLIArgumentParser()
    private let renderer = CompatibilityReportRenderer()

    func run(arguments: [String], httpClient: any HTTPClient) async -> CLIExecution {
        let parsed: CLIArgumentResult
        do {
            parsed = try parser.parse(arguments)
        } catch {
            return CLIExecution(
                exitCode: .inputError,
                output: "Error: \(error.localizedDescription)\n\n\(CLIArgumentParser.help)"
            )
        }

        guard case let .options(options) = parsed else {
            return CLIExecution(exitCode: .success, output: CLIArgumentParser.help)
        }

        let sourceJSON: Data
        do {
            sourceJSON = try Data(contentsOf: URL(fileURLWithPath: options.sourcePath))
        } catch {
            return inputFailure("Unable to read the source file.", usesJSON: options.usesJSONOutput)
        }
        guard (try? JSONSerialization.jsonObject(with: sourceJSON)) != nil else {
            return inputFailure("The source file is not valid JSON.", usesJSON: options.usesJSONOutput)
        }

        let report = await BookSourceCompatibilityRunner(
            httpClient: httpClient,
            textDecoder: FoundationTextDecoder(),
            maximumPageCount: options.maximumPageCount
        ).run(
            sourceJSON: sourceJSON,
            keyword: options.keyword,
            searchPage: options.searchPage,
            bookIndex: options.bookIndex,
            chapterIndex: options.chapterIndex
        )
        let dto = CompatibilityReportDTO(report: report)
        return CLIExecution(
            exitCode: report.isSuccessful ? .success : .compatibilityFailure,
            output: render(dto, usesJSON: options.usesJSONOutput)
        )
    }

    private func inputFailure(_ message: String, usesJSON: Bool) -> CLIExecution {
        CLIExecution(
            exitCode: .inputError,
            output: render(.inputFailure(message), usesJSON: usesJSON)
        )
    }

    private func render(_ report: CompatibilityReportDTO, usesJSON: Bool) -> String {
        if usesJSON, let json = try? renderer.json(report) { return json }
        return renderer.humanReadable(report)
    }
}
