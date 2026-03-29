import ArgumentParser
import Fluent
import Foundation

extension UserCommands {
	struct Set: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "set",
			abstract: "Change a user's attributes.",
			usage: """
				notendb user set [--format <format>] (<username> | -id <userID>) [--username <new-username>] [--password <password>] [--level <level>]
				notendb user set (--help | --version)
				""",
			version: "0.1.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Argument(help: "The username that changes should be applied to.")
		var username: String?
		
		@Option(name: .customLong("id", withSingleDash: true), help: "Specify a userID instead of a username to apply changes to.")
		var userID: UUID?
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		@Option(name: [.customShort("u"), .customLong("username")], help: "Set a new username.")
		var newUsername: String?
		
		@Option(name: [.customShort("l"), .customLong("level")], help: "Set a new permission level.")
		var newLevel: User.Level?
		
		@Option(name: [.customShort("p"), .customLong("password")], help: "Set a new password.")
		var newPassword: String?
		
		func run() async throws {
			struct UserDTO: Encodable, Sendable {
				var id: UUID
				var username: String
				var level: User.Level
			}
			
			try await withApplicationDBTransaction { db, _ in
				guard let user = try await getUser(on: db) else {
					throw AppError.modelNotFound(description: "User not found.")
				}
				
				if let newUsername = self.newUsername {
					user.username = newUsername
				}
				
				if let newPassword = self.newPassword {
					user.password = User.hashPassword(newPassword, salt: user.salt)
				}
				
				if let newLevel = self.newLevel {
					user.level = newLevel
				}
				
				try await user.update(on: db)
				
				let dto = UserDTO(
					id: try user.requireID(),
					username: user.username,
					level: user.level,
				)
				
				// we do this within the transaction so if the output fails, no data is altered
				print(try self.format.format(dto))
			}
		}
		
		func getUser(on db: Database) async throws -> User? {
			if let userID {
				guard username == nil else {
					throw AppError.invalidInput(description: "Cannot accept both a username and userID.")
				}
				
				return try await User.query(on: db)
					.filter(\.$id == userID)
					.first()
			} else if let username {
				return try await User.query(on: db)
					.filter(\.$username == username)
					.first()
			} else {
				throw AppError.invalidInput(description: "Neither username nor userID was specified.")
			}
		}
	}
}
