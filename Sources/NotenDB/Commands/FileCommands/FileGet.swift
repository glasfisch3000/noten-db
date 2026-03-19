import ArgumentParser
import Fluent
import Foundation

extension FileCommands {
	struct Get: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "get",
			abstract: "Get information about a sheet/thumbnail file.",
			usage: """
				notendb file get [--format <format>] <sheetID>
				notendb file get (--help | --version)
				""",
			version: "0.1.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Argument(help: "The sheet ID to look up.")
		var sheetID: Sheet.IDValue
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			struct ResultDTO: Encodable, Sendable {
				var sheetID: UUID
				var path: String?
				var size: Int64?
				var thumbnailPath: String?
				var thumbnailSize: Int64?
			}
			
			let result = try await withApplication { app, storage in
				let sheetInfo = try await storage.getSheet(sheetID)
				let thumbnailInfo = try await storage.getThumbnail(sheetID)
				
				return ResultDTO(
					sheetID: sheetID,
					path: sheetInfo?.0.string,
					size: sheetInfo?.1.size,
					thumbnailPath: thumbnailInfo?.0.string,
					thumbnailSize: thumbnailInfo?.1.size
				)
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(result))
		}
	}
}
