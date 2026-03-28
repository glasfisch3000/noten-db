import struct Foundation.UUID
import protocol Vapor.Content

struct SheetDTO: Codable, Content {
	struct Creator: Codable {
		var username: String
	}
	
	var id: UUID
	var title: String
	var composer: String?
	var arranger: String?
	var creator: Creator?
	
	init(id: UUID, title: String, composer: String?, arranger: String?, creator: Creator?) {
		self.id = id
		self.title = title
		self.composer = composer
		self.arranger = arranger
		self.creator = creator
	}
	
	init(_ sheet: Sheet) throws {
		self.id = try sheet.requireID()
		self.title = sheet.title
		self.composer = sheet.composer
		self.arranger = sheet.arranger
		self.creator = sheet.$createdBy.value.flatMap {
			Self.Creator(username: $0.username)
		}
	}
}
