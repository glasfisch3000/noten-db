import ArgumentParser
import Fluent
import Foundation

extension UserCommands {
	struct Get: AsyncParsableCommand {
		static let configuration = CommandConfiguration(
			commandName: "get",
			abstract: "Get information about a single user.",
			usage: """
				notendb user get [--format <format>] (<username> | -id <userID>)
				notendb user get (--help | --version)
				""",
			version: "0.0.0",
			shouldDisplay: true,
			helpNames: .shortAndLong
		)
		
		@Argument(help: "The username to look up.")
		var username: String?
		
		@Option(name: .customLong("id", withSingleDash: true), help: "Specify a userID instead of a username to look up.")
		var userID: UUID?
		
		@Option(name: .shortAndLong, help: "Specify the output formatting.")
		var format: OutputFormat = .json
		
		func run() async throws {
			struct UserDTO: Encodable, Sendable {
				var id: UUID
				var username: String
				var level: User.Level
			}
			
			let userDTO = try await withApplicationDBTransaction { db, _ in
				guard let user = try await getUser(on: db) else {
					throw AppError.modelNotFound(description: "User not found.")
				}
				
				return UserDTO(
					id: try user.requireID(),
					username: user.username,
					level: user.level,
				)
			}
			
			// do this after the transaction so the app can already be closed
			print(try self.format.format(userDTO))
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
