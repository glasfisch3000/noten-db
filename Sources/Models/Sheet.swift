import Fluent
import Foundation

final class Sheet: Model, @unchecked Sendable {
	static let schema: String = "sheets"
	
	@ID(key: .id)
	var id: UUID?
	
	@Field(key: "title")
	var title: String
	
	@Field(key: "composer")
	var composer: String?
	
	@Field(key: "year")
	var year: Int?
	
	@Parent(key: "created_by")
	var createdBy: User
	
	init() { }
	
	init(id: UUID? = nil, title: String, composer: String?, year: Int?, createdBy: User.IDValue) {
		self.id = id
		self.title = title
		self.composer = composer
		self.year = year
		self.$createdBy.id = createdBy
	}
}

struct CreateSheetMigration: AsyncMigration {
	func prepare(on database: any Database) async throws {
		try await database.schema("sheets")
			.id()
			.field("title", .string, .required)
			.field("composer", .string)
			.field("year", .int)
			.field("created_by", .uuid, .required, .references("users", .id))
			.create()
	}
	
	func revert(on database: any Database) async throws {
		try await database.schema("sheets")
			.delete()
	}
}
