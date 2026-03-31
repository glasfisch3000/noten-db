import Fluent
import Foundation

final class Sheet: Model, @unchecked Sendable, Comparable {
	static let schema: String = "sheets"
	
	@ID(key: .id)
	var id: UUID?
	
	@Field(key: "title")
	var title: String
	
	@Field(key: "variant")
	var variant: String?
	
	@Field(key: "composer")
	var composer: String?
	
	@Field(key: "arranger")
	var arranger: String?
	
	@Field(key: "voices")
	var voices: String?
	
	@Parent(key: "created_by")
	var createdBy: User
	
	@Timestamp(key: "deleted_at", on: .delete)
	var deletedAt: Date?
	
	init() { }
	
	init(id: UUID? = nil, title: String, variant: String?, composer: String?, arranger: String?, voices: String?, createdBy: User.IDValue) {
		self.id = id
		self.title = title
		self.variant = variant
		self.composer = composer
		self.arranger = arranger
		self.voices = voices
		self.$createdBy.id = createdBy
		self.deletedAt = nil
	}
	
	static func < (lhs: Sheet, rhs: Sheet) -> Bool {
		if let c = compare(lhs, rhs, path: { $0.title.lowercased() }) { return c }
		if let c = compare(lhs, rhs, path: { $0.composer?.lowercased() }) { return c }
		if let c = compare(lhs, rhs, path: { $0.arranger?.lowercased() }) { return c }
		if let c = compare(lhs, rhs, path: { $0.variant?.lowercased() }) { return c }
		if let c = compare(lhs, rhs, path: { $0.voices?.lowercased() }) { return c }
		return compare(lhs, rhs, path: \.id) ?? false
	}
	
	static func == (lhs: Sheet, rhs: Sheet) -> Bool {
		lhs.title.lowercased() == rhs.title.lowercased()
		&& lhs.composer?.lowercased() == rhs.composer?.lowercased()
		&& lhs.arranger?.lowercased() == rhs.arranger?.lowercased()
		&& lhs.variant?.lowercased() == rhs.variant?.lowercased()
		&& lhs.voices?.lowercased() == rhs.voices?.lowercased()
		&& lhs.id == rhs.id
	}
	
	private static func compare<Property: Comparable>(_ lhs: Sheet, _ rhs: Sheet, path: (Sheet) -> Property?) -> Bool? {
		if let l = path(lhs) {
			if let r = path(rhs) {
				if l < r { return true }
				if r < l { return false }
				return nil
			} else {
				return true
			}
		} else if path(rhs) != nil {
			return false
		} else {
			return nil
		}
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
	
	struct AddSoftDeleteMigration: AsyncMigration {
		var name: String { "NotenDB.AddSoftDeleteMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("sheets")
				.field("deleted_at", .datetime)
				.update()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("sheets")
				.deleteField("deleted_at")
				.update()
		}
	}
	
	struct AddVariantMigration: AsyncMigration {
		var name: String { "NotenDB.Sheet.AddVariantMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("sheets")
				.field("variant", .string)
				.update()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("sheets")
				.deleteField("variant")
				.update()
		}
	}
	
	struct AddVoicesMigration: AsyncMigration {
		var name: String { "NotenDB.Sheet.AddVoicesMigration" }
		
		func prepare(on database: any Database) async throws {
			try await database.schema("sheets")
				.field("voices", .string)
				.update()
		}
		
		func revert(on database: any Database) async throws {
			try await database.schema("sheets")
				.deleteField("voices")
				.update()
		}
	}
}
