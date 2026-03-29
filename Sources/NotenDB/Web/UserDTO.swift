import struct Foundation.UUID
import protocol Vapor.Content

struct UserDTO: Codable, Content {
	var id: UUID
	var username: String
	var level: User.Level
	
	init(id: UUID, username: String, level: User.Level) {
		self.id = id
		self.username = username
		self.level = level
	}
	
	init(_ user: User) throws {
		self.id = try user.requireID()
		self.username = user.username
		self.level = user.level
	}
}
