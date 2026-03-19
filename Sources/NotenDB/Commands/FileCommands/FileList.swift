import ArgumentParser
import Foundation

extension FileCommands {
	struct List: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "list",
			abstract: "List all sheet and thumbnail files.",
			usage: """
				notendb file list [--format <format>]
				notendb file list (--help | --version)
				""",
			version: "0.1.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			// holds information on each entry about whether its sheet and thumbnail file exist
			struct Result: Codable {
				var sheetFile: String?
				var thumbnailFile: String?
				
				init() { }
			}
			
			let results = try await withApplication { app, storage in
				// create dictionaries for both sheet and thumbnail files
				let sheets: [UUID: String] = Dictionary(uniqueKeysWithValues:
					try await storage.listSheets()
						.compactMap { file in
							UUID(uuidString: file.name.string)
								.map { ($0, file.path.string) }
						}
				)
				let thumbnails: [UUID: String] = Dictionary(uniqueKeysWithValues:
					try await storage.listThumbnails()
						.compactMap { file in
							UUID(uuidString: file.name.string)
								.map { ($0, file.path.string) }
						}
				)
				
				var registry = [UUID: Result]()
				// register all sheet files
				for (id, path) in sheets {
					var entry = registry[id] ?? Result()
					entry.sheetFile = path
					registry[id] = entry
				}
				// register all thumbnail files
				for (id, path) in thumbnails {
					var entry = registry[id] ?? Result()
					entry.thumbnailFile = path
					registry[id] = entry
				}
				
				return registry
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(results))
		}
	}
}
