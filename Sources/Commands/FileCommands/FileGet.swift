import ArgumentParser
import Fluent
import Foundation

extension FileCommands {
	struct Get: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "get",
			abstract: "Get information about a sheet file.",
			usage: """
				notendb file get [--format <format>] <sheetID>
				notendb file get (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Argument(help: "The sheet ID to look up.")
		var sheetID: Sheet.IDValue
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			struct FileDTO: Encodable, Sendable {
				var sheetID: UUID
				var path: String
				var size: Int64
			}
			
			let fileDTO = try await withApplication { app, storage -> FileDTO? in
				guard let (dir, info) = try await storage.getInfo(sheetID: sheetID) else {
					return nil
				}
				
				return FileDTO(sheetID: sheetID, path: dir.string, size: info.size)
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(fileDTO))
		}
	}
}
