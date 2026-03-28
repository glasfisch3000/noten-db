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
	
	@Field(key: "arranger")
	var arranger: String?
	
	@Parent(key: "created_by")
	var createdBy: User
	
	init() { }
	
	init(id: UUID? = nil, title: String, composer: String?, arranger: String?, createdBy: User.IDValue) {
		self.id = id
		self.title = title
		self.composer = composer
		self.arranger = arranger
		self.$createdBy.id = createdBy
	}
}

extension Sheet {
	struct CreateSheetMigration: AsyncMigration {
		var name: String { "NotenDB.CreateSheetMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("sheets")
				.id()
				.field("title", .string, .required)
				.field("composer", .string)
				.field("arranger", .string)
				.field("year", .int)
				.field("created_by", .uuid, .required, .references("users", .id))
				.create()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("sheets")
				.delete()
		}
	}
	
	struct DeleteYearMigration: AsyncMigration {
		var name: String { "NotenDB.DeleteYearMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("sheets")
				.deleteField("year")
				.update()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("sheets")
				.field("year", .int)
				.update()
		}
	}
}
