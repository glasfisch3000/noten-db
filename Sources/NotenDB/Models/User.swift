import ArgumentParser
import Fluent
import Foundation
import Crypto

final class User: Model, @unchecked Sendable, ModelSessionAuthenticatable {
	enum Level: String, Codable, ExpressibleByArgument {
		case viewer
		case contributor
		case admin
	}
	
	static let schema: String = "users"
	
	@ID(key: .id)
	var id: UUID?
	
	@Field(key: "username")
	var username: String
	
	@Field(key: "salt")
	var salt: UUID
	
	@Field(key: "passwordSHA256")
	var password: Data
	
	@Enum(key: "level")
	var level: Level
	
	init() { }
	
	init(id: UUID? = nil, username: String, salt: UUID = UUID(), password: String, level: Level) {
		self.id = id
		self.username = username
		self.salt = salt
		self.password = Self.hashPassword(password, salt: salt)
		self.level = level
	}
	
	static func hashPassword(_ password: String, salt: UUID) -> Data {
		var hasher = SHA256()
		hasher.update(data: Data(password.utf8))
		hasher.update(data: Data(salt.uuidString.utf8))
		return Data(hasher.finalize())
	}
	
	func verify(password: String) -> Bool {
		self.password.elementsEqual(Self.hashPassword(password, salt: self.salt))
	}
	
	var canUpload: Bool {
		switch level {
		case .viewer: false
		case .contributor, .admin: true
		}
	}
	
	func canEdit(_ sheet: Sheet, on db: any Database) async throws -> Bool {
		switch level {
		case .viewer: false
		case .contributor: try (await sheet.$createdBy.get(on: db).requireID() == self.requireID()) // can only edit their own uploads
		case .admin: true
		}
	}
	
	func canDelete(_ sheet: Sheet, on db: any Database) async throws -> Bool {
		switch level {
		case .viewer: false
		case .contributor: try (await sheet.$createdBy.get(on: db).requireID() == self.requireID()) // can only delete their own uploads
		case .admin: true
		}
	}
}

extension User {
	struct CreateUserMigration: AsyncMigration {
		var name: String { "NotenDB.CreateUserMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("users")
				.id()
				.field("username", .string, .required)
				.field("salt", .uuid, .required)
				.field("passwordSHA256", .data, .required)
				.unique(on: "username")
				.create()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("users")
				.delete()
		}
	}
	
	struct AddUserLevelMigration: AsyncMigration {
		var name: String { "NotenDB.AddUserLevelMigration"}
		
		func prepare(on database: any Database) async throws {
			let userLevel = try await database.enum("user_level")
				.case("viewer")
				.case("contributor")
				.case("admin")
				.create()
			
			try await database.schema("users")
				.field("level", userLevel, .required, .sql(.default("viewer")))
				.update()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("users")
				.deleteField("level")
				.update()
			
			try await database.enum("user_level")
				.delete()
		}
	}
}
