import ArgumentParser
import Foundation

extension UserCommands {
	struct Create: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "create",
			abstract: "Create a new user.",
			usage: """
				notendb user create [--format <format>] --username <username> --password <password>
				notendb user create (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong,
			aliases: ["add"]
		)
		
		@Option(name: .shortAndLong, help: "The new user's username.")
		var username: String
		
		@Option(name: .shortAndLong, help: "The new user's login password.")
		var password: String
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			struct UserDTO: Encodable, Sendable {
				var id: UUID
				var username: String
			}
			
			try await withApplicationDBTransaction { db, _ in
				let user = User(username: self.username, password: self.password)
				try await user.create(on: db)
				
				let userDTO = UserDTO(
					id: try user.requireID(),
					username: user.username,
				)
				
				// do this within the transaction so if the output fails, no data is saved
				print(try self.format.format(userDTO))
			}
		}
	}
}
