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
		let sheet = try await fetchSheet(request)
		let download = (try? request.query.get(Bool.self, at: "download")) ?? false
		
		guard let (path, _) = try await storage.getSheet(try sheet.requireID()) else {
			throw Abort(.notFound)
		}
		
		let response = try await request.fileio.asyncStreamFile(at: path.string, mediaType: .pdf)
		if download {
			response.headers.contentDisposition = .init(.attachment)
		}
		
		print(response.headers)
		
		return response
	}
	
	func getThumbnail(request: Request) async throws -> Response {
		let sheet = try await fetchSheet(request)
		
		guard let path = try await storage.getThumbnailOrConvert(try sheet.requireID()) else {
			throw Abort(.notFound)
		}
		
		return try await request.fileio.asyncStreamFile(at: path.string, mediaType: .png)
	}
	
	// get the confirmation page for deleting a sheet
	func getDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var user: UserDTO
			var sheet: SheetDTO
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		guard try await user.canDelete(sheet, on: request.db) else {
			throw Abort(.forbidden)
		}
		
		let context = Context(user: try UserDTO(user), sheet: try .init(sheet))
		return try await request.view.render("Pages/delete-item", context)
	}
	
	// delete a sheet and return a result page
	func postDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var user: UserDTO
			var success: Bool
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		guard try await user.canDelete(sheet, on: request.db) else {
			throw Abort(.forbidden)
		}
		
		let success: Bool
		
		do {
			try await sheet.delete(force: false, on: request.db)
			success = true
		} catch {
			success = false
		}
		
		let context = Context(user: try UserDTO(user), success: success)
		return try await request.view.render("Pages/delete-item", context)
	}
	
	func getEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var user: UserDTO
			var sheet: SheetDTO
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		guard try await user.canEdit(sheet, on: request.db) else {
			throw Abort(.forbidden)
		}
		
		let context = Context(user: try UserDTO(user), sheet: try .init(sheet))
		return try await request.view.render("Pages/edit-item", context)
	}
	
	func postEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var user: UserDTO
			var sheet: SheetDTO
			var success: Bool
		}
		
		struct EditData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				
				self.title = try container.decode(String.self, forKey: .title)
				if title.isEmpty { throw RequestError.invalidFormat }
				
				self.composer = try container.decodeIfPresent(String.self, forKey: .composer)
				if let composer, composer.isEmpty { self.composer = nil }
				
				self.arranger = try container.decodeIfPresent(String.self, forKey: .arranger)
				if let arranger, arranger.isEmpty { self.arranger = nil }
			}
		}
		
		let user = try request.auth.require(User.self)
		let sheet = try await fetchSheet(request)
		
		guard try await user.canEdit(sheet, on: request.db) else {
			throw Abort(.forbidden)
		}
		
		do {
			// collect data
			let edit: EditData = try await request.decodeBody(as: .urlEncodedForm, maxBytes: 10_000) // 10KB should be enough
			
			sheet.title = edit.title
			sheet.composer = edit.composer
			sheet.arranger = edit.arranger
			try await sheet.update(on: request.db)
			
			let context = Context(user: try UserDTO(user), sheet: try .init(sheet), success: true)
			return try await request.view.render("Pages/edit-item", context)
		} catch {
			let context = Context(user: try UserDTO(user), sheet: try .init(sheet), success: false)
			return try await request.view.render("Pages/edit-item", context)
		}
	}
}
