import Vapor
import Leaf
import Fluent

struct ItemRoutes: RouteCollection {
	enum RequestError: Error {
		case invalidFormat
	}
	
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes.get("file.pdf", use: getFile(request:))
		routes.get("thumbnail.png", use: getThumbnail(request:))
		
		routes.get("delete", use: getDeleteItem(request:))
		routes.post("delete", use: postDeleteItem(request:))
		
		routes.get("edit", use: getEditItem(request:))
		routes.on(.POST, "edit", body: .stream, use: postEditItem(request:))
	}
	
	func fetchSheet(_ request: Request) async throws -> Sheet {
		guard let sheetID = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		if let sheet = try await Sheet
			.query(on: request.db)
			.filter(\.$id == sheetID)
			.with(\.$createdBy)
			.first() {
			return sheet
		} else {
			throw Abort(.notFound)
		}
	}
}

extension ItemRoutes {
	func getFile(request: Request) async throws -> Response {
		guard let id = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		guard let (path, _) = try await storage.getSheet(id) else {
			throw Abort(.notFound)
		}
		
		return try await request.fileio.asyncStreamFile(at: path.string, mediaType: .pdf)
	}
	
	func getThumbnail(request: Request) async throws -> Response {
		guard let id = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		guard let path = try await storage.getThumbnailOrConvert(id) else {
			throw Abort(.notFound)
		}
		
		return try await request.fileio.asyncStreamFile(at: path.string, mediaType: .png)
	}
	
	// get the confirmation page for deleting a sheet
	func getDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var username: String
			var sheet: SheetDTO
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		let context = Context(username: user.username, sheet: try .init(sheet))
		return try await request.view.render("Pages/delete-item", context)
	}
	
	// delete a sheet and return a result page
	func postDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var username: String
			var success: Bool
		}
		
		let user = try request.auth.require(User.self)
		
		guard let sheetID = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		let success: Bool
		
		do {
			try await request.db.transaction { db in
				try await Sheet.query(on: db)
					.filter(\.$id == sheetID)
					.delete()
				
				try await storage.remove(sheetID)
			}
			success = true
		} catch {
			success = false
		}
		
		let context = Context(username: user.username, success: success)
		return try await request.view.render("Pages/delete-item", context)
	}
	
	func getEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var username: String
			var sheet: SheetDTO
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		let context = Context(username: user.username, sheet: try .init(sheet))
		return try await request.view.render("Pages/edit-item", context)
	}
	
	func postEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var username: String
			var sheet: SheetDTO
			var success: Bool
		}
		
		struct EditData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			var year: Int?
			
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				
				self.title = try container.decode(String.self, forKey: .title)
				if title.isEmpty { throw RequestError.invalidFormat }
				
				self.composer = try container.decodeIfPresent(String.self, forKey: .composer)
				if let composer, composer.isEmpty { self.composer = nil }
				
				self.arranger = try container.decodeIfPresent(String.self, forKey: .arranger)
				if let arranger, arranger.isEmpty { self.arranger = nil }
				
				self.year = try container.decodeIfPresent(String.self, forKey: .year).flatMap(Int.init(_:))
			}
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		do {
			// collect data
			let edit: EditData = try await request.decodeBody(as: .urlEncodedForm, maxBytes: 10_000) // 10KB should be enough
			
			sheet.title = edit.title
			sheet.composer = edit.composer
			sheet.arranger = edit.arranger
			sheet.year = edit.year
			try await sheet.update(on: request.db)
			
			let context = Context(username: user.username, sheet: try .init(sheet), success: true)
			return try await request.view.render("Pages/edit-item", context)
		} catch {
			let context = Context(username: user.username, sheet: try .init(sheet), success: false)
			return try await request.view.render("Pages/edit-item", context)
		}
	}
}
