import ArgumentParser
import Fluent
import Foundation

extension UserCommands {
	struct Delete: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "delete",
			abstract: "Delete a user from the database.",
			usage: """
				notendb user delete [--format <format>] (<username> | -id <userID>)
				notendb user delete (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Argument(help: "The username to delete.")
		var username: String?
		
		@Option(name: .customLong("id", withSingleDash: true), help: "Specify a userID instead of a username to delete.")
		var userID: UUID?
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
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
				
				let dto = UserDTO(
					id: try user.requireID(),
					username: user.username,
					level: user.level,
				)
				
				try await user.delete(force: false, on: db)
				
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
