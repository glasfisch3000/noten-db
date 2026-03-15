import Fluent
import Foundation
import Crypto

final class User: Model, @unchecked Sendable, ModelSessionAuthenticatable {
	static let schema: String = "users"
	
	@ID(key: .id)
	var id: UUID?
	
	@Field(key: "username")
	var username: String
	
	@Field(key: "salt")
	var salt: UUID
	
	@Field(key: "passwordSHA256")
	var password: Data
	
	init() { }
	
	init(id: UUID? = nil, username: String, salt: UUID = UUID(), password: String) {
		self.id = id
		self.username = username
		self.salt = salt
		self.password = Self.hashPassword(password, salt: salt)
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
}

struct CreateUserMigration: AsyncMigration {
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
