import ArgumentParser
import Foundation

extension UserCommands {
	struct List: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "list",
			abstract: "List all users.",
			usage: """
				notendb user list [--format <format>]
				notendb user list (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			struct UserDTO: Encodable, Sendable {
				var id: UUID
				var username: String
			}
			
			let userDTOs = try await withApplicationDBTransaction { db, _ in
				try await User.query(on: db)
					.all()
					.map {
						UserDTO(
							id: try $0.requireID(),
							username: $0.username,
						)
					}
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(userDTOs))
		}
	}
}
