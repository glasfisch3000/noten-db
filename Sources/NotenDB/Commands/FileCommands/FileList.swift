import ArgumentParser
import Foundation

extension FileCommands {
	struct List: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "list",
			abstract: "List all sheet files.",
			usage: """
				notendb file list [--format <format>]
				notendb file list (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			let files = try await withApplication { app, storage in
				try await storage.list()
					.compactMap {
						UUID(uuidString: $0.name.string)
					}
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(files))
		}
	}
}
