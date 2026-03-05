import Vapor
import Leaf
import Fluent
import NIOCore

struct StandardWebRoutes {
	enum RequestError: Error {
		case invalidPagingSize(UInt)
		case tooLarge
		case invalidFormat
	}
	
	var storage: FileStorage
	
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

extension StandardWebRoutes: RouteCollection {
	func boot(routes: any RoutesBuilder) throws {
		routes.get(use: index(request:))
		
		routes.get("upload", use: upload(request:))
		routes.on(.POST, "upload", body: .stream, use: postUpload(request:))
		
		routes.group(":id") {
			$0.get("delete", use: getDeleteItem(request:))
			$0.post("delete", use: postDeleteItem(request:))
			
			$0.get("edit", use: getEditItem(request:))
			$0.on(.POST, "edit", body: .stream, use: postEditItem(request:))
		}
	}
	
	func index(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
			var sheets: [SheetDTO]
			
			var pageNumber: UInt
			var pageCount: UInt
			var pageSize: UInt
			var total: UInt
		}
		
		struct Query: Codable {
			var page: UInt?
			var size: UInt?
		}
		
		let page = try PageAttributes(request, requireUser: true)
		
		let query = try request.query.decode(Query.self)
		if let size = query.size, size < 1 {
			throw RequestError.invalidPagingSize(size)
		}
		
		let sheets = try await Sheet
			.query(on: request.db)
			.with(\.$createdBy)
			.page(withIndex: Int(query.page ?? 0), size: Int(query.size ?? 30))
		
		let context = Context(
			page: page,
			sheets: try sheets.items.map(SheetDTO.init(_:)),
			pageNumber: UInt(sheets.metadata.page),
			pageCount: UInt(sheets.metadata.pageCount),
			pageSize: UInt(sheets.metadata.per),
			total: UInt(sheets.metadata.total)
		)
		
		return try await request.view.render("Pages/index", context)
	}
	
	func upload(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
		}
		
		let context = Context(page: try PageAttributes(request, requireUser: true, requireReturn: true))
		return try await request.view.render("Pages/upload", context)
	}
	
	func postUpload(request: Request) async throws -> View {
		struct UploadData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			var year: Int?
			var file: Data
			
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				
				self.title = try container.decode(String.self, forKey: .title)
				if title.isEmpty { throw RequestError.invalidFormat }
				
				self.composer = try container.decodeIfPresent(String.self, forKey: .composer)
				if let composer, composer.isEmpty { self.composer = nil }
				
				self.arranger = try container.decodeIfPresent(String.self, forKey: .arranger)
				if let arranger, arranger.isEmpty { self.arranger = nil }
				
				self.year = try container.decodeIfPresent(String.self, forKey: .year).flatMap(Int.init(_:))
				self.file = try container.decode(Data.self, forKey: .file)
			}
		}
		
		struct Context: Encodable {
			enum PostError: String, Error, Codable {
				case unreadable
				case tooLarge
				case `internal`
			}
			
			var page: PageAttributes
			
			var success: Bool
			var error: PostError? = nil
		}
		
		let page = try PageAttributes(request, requireUser: true, requireReturn: true)
		
		do {
			// collect data
			let uploadData = try await request.decodeBody(UploadData.self, as: .formData, maxBytes: 15_000_000) // 15MB
			
			// try to store data in database and file at once. if one fails, return an error
			try await request.db.transaction { db in
				let sheet = Sheet(
					title: uploadData.title,
					composer: uploadData.composer,
					arranger: uploadData.arranger,
					year: uploadData.year,
					createdBy: try page.user!.requireID()
				)
				try await sheet.create(on: db)
				
				try await storage.create(sheetID: try sheet.requireID(), contents: uploadData.file)
			}
			
			let context = Context(page: page, success: true)
			return try await request.view.render("Pages/upload", context)
		} catch _ as NIOTooManyBytesError {
			let context = Context(page: page, success: false, error: .tooLarge)
			return try await request.view.render("Pages/upload", context)
		} catch _ as Abort, _ as DecodingError {
			let context = Context(page: page, success: false, error: .unreadable)
			return try await request.view.render("Pages/upload", context)
		} catch {
			let context = Context(page: page, success: false, error: .internal)
			return try await request.view.render("Pages/upload", context)
		}
	}
	
	// get the confirmation page for deleting a sheet
	func getDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
			var sheet: SheetDTO
		}
		
		let page = try PageAttributes(request, requireUser: true, requireReturn: true)
		let sheet = try await fetchSheet(request)
		
		let context = Context(page: page, sheet: try .init(sheet))
		return try await request.view.render("Pages/delete-item", context)
	}
	
	// delete a sheet and return a result page
	func postDeleteItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
			var success: Bool
		}
		
		let page = try PageAttributes(request, requireUser: true, requireReturn: true)
		
		guard let sheetID = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		let success: Bool
		
		do {
			try await request.db.transaction { db in
				try await Sheet.query(on: db)
					.filter(\.$id == sheetID)
					.delete()
				
				try await storage.remove(sheetID: sheetID)
			}
			success = true
		} catch {
			success = false
		}
		
		let context = Context(page: page, success: success)
		return try await request.view.render("Pages/delete-item", context)
	}
	
	func getEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
			var sheet: SheetDTO
		}
		
		let page = try PageAttributes(request, requireUser: true, requireReturn: true)
		let sheet = try await fetchSheet(request)
		
		let context = Context(page: page, sheet: try .init(sheet))
		return try await request.view.render("Pages/edit-item", context)
	}
	
	// delete a sheet and return a result page
	func postEditItem(request: Request) async throws -> View {
		struct Context: Encodable {
			var page: PageAttributes
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
		
		let page = try PageAttributes(request, requireUser: true, requireReturn: true)
		let sheet = try await fetchSheet(request)
		
		do {
			// collect data
			let edit: EditData = try await request.decodeBody(as: .urlEncodedForm, maxBytes: 10_000) // 10KB should be enough
			
			sheet.title = edit.title
			sheet.composer = edit.composer
			sheet.arranger = edit.arranger
			sheet.year = edit.year
			try await sheet.update(on: request.db)
			
			let context = Context(page: page, sheet: try .init(sheet), success: true)
			return try await request.view.render("Pages/edit-item", context)
		} catch {
			let context = Context(page: page, sheet: try .init(sheet), success: false)
			return try await request.view.render("Pages/edit-item", context)
		}
	}
}
