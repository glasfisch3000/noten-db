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
	
	struct SheetDTO: Codable {
		struct Creator: Codable {
			var username: String
		}
		
		var id: UUID
		var title: String
		var composer: String?
		var arranger: String?
		var year: Int?
		var creator: Creator?
		
		init(id: UUID, title: String, composer: String?, arranger: String?, year: Int?, creator: Creator?) {
			self.id = id
			self.title = title
			self.composer = composer
			self.arranger = arranger
			self.year = year
			self.creator = creator
		}
		
		init(_ sheet: Sheet) throws {
			self.id = try sheet.requireID()
			self.title = sheet.title
			self.composer = sheet.composer
			self.arranger = sheet.arranger
			self.year = sheet.year
			self.creator = sheet.$createdBy.value.flatMap {
				Self.Creator(username: $0.username)
			}
		}
	}
	
	var storage: FileStorage
	
	func requireUser(_ request: Request) throws -> User {
		if let user = request.auth.get(User.self) {
			return user
		} else {
			throw AuthError.missingLogin
		}
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
	
	func parseReturnPath(_ request: Request) -> String? {
		try? request.query.get(String.self, at: "return")
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
		}
	}
	
	func index(request: Request) async throws -> View {
		struct Context: Codable {
			var username: String
			var sheets: [SheetDTO]
			
			var page: UInt
			var pageCount: UInt
			var pageSize: UInt
			var total: UInt
		}
		
		struct Query: Codable {
			var page: UInt?
			var size: UInt?
		}
		
		let user = try requireUser(request)
		
		let query = try request.query.decode(Query.self)
		if let size = query.size, size < 1 {
			throw RequestError.invalidPagingSize(size)
		}
		
		let sheets = try await Sheet
			.query(on: request.db)
			.with(\.$createdBy)
			.page(withIndex: Int(query.page ?? 0), size: Int(query.size ?? 30))
		
		let context = Context(
			username: user.username,
			sheets: try sheets.items.map(SheetDTO.init(_:)),
			page: UInt(sheets.metadata.page),
			pageCount: UInt(sheets.metadata.pageCount),
			pageSize: UInt(sheets.metadata.per),
			total: UInt(sheets.metadata.total)
		)
		
		return try await request.view.render("Pages/index", context)
	}
	
	func upload(request: Request) async throws -> View {
		struct Context: Codable {
			var username: String
		}
		
		let user = try requireUser(request)
		let context = Context(username: user.username)
		
		return try await request.view.render("Pages/upload", context)
	}
	
	func postUpload(request: Request) async throws -> View {
		struct UploadData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			var year: String?
			var file: Data
		}
		
		struct Context: Codable {
			enum PostError: String, Error, Codable {
				case unreadable
				case tooLarge
				case `internal`
			}
			
			var username: String
			var success: Bool
			var error: PostError? = nil
		}
		
		// authenticate
		let user = try requireUser(request)
		
		// collect data
		let uploadData: UploadData
		let year: Int?
		do {
			let buffer = if let data = request.body.data {
				data
			} else {
				try await request.body.collect(upTo: 10_000_000) // max 10MB
			}
			
			let decoder = try ContentConfiguration.global.requireDecoder(for: .formData)
			var decoded = try decoder.decode(UploadData.self, from: buffer, headers: request.headers)
			
			if decoded.title.isEmpty {
				throw RequestError.invalidFormat
			}
			
			if let composer = decoded.composer, composer.isEmpty {
				decoded.composer = nil
			}
			
			if let arranger = decoded.arranger, arranger.isEmpty {
				decoded.arranger = nil
			}
			
			year = if let string = decoded.year {
				if string.isEmpty {
					nil
				} else if let parsed = Int(string) {
					parsed
				} else {
					throw RequestError.invalidFormat
				}
			} else {
				nil
			}
			
			uploadData = decoded
		} catch _ as NIOTooManyBytesError {
			let context = Context(username: user.username, success: false, error: .tooLarge)
			return try await request.view.render("Pages/upload", context)
		} catch {
			let context = Context(username: user.username, success: false, error: .unreadable)
			return try await request.view.render("Pages/upload", context)
		}
		
		// try to store data in database and file at once. if one fails, return an error page
		do {
			return try await request.db.transaction { db in
				let sheet = Sheet(
					title: uploadData.title,
					composer: uploadData.composer,
					arranger: uploadData.arranger,
					year: year,
					createdBy: try user.requireID()
				)
				try await sheet.create(on: db)
				
				try await storage.create(sheetID: try sheet.requireID(), contents: uploadData.file)
				
				let context = Context(username: user.username, success: true)
				return try await request.view.render("Pages/upload", context)
			}
		} catch {
			let context = Context(username: user.username, success: false, error: .internal)
			return try await request.view.render("Pages/upload", context)
		}
	}
	
	// get the confirmation page for deleting a sheet
	func getDeleteItem(request: Request) async throws -> View {
		struct Context: Codable {
			var username: String
			var sheet: SheetDTO
			var `return`: String
		}
		
		let user = try requireUser(request)
		let sheet = try await fetchSheet(request)
		let returnPath = parseReturnPath(request) ?? "/"
		
		let context = Context(username: user.username, sheet: try .init(sheet), return: returnPath)
		return try await request.view.render("Pages/delete", context)
	}
	
	// delete a sheet and return a result page
	func postDeleteItem(request: Request) async throws -> View {
		struct Context: Codable {
			var username: String
			var sheet: SheetDTO
			var `return`: String
			var success: Bool
		}
		
		let user = try requireUser(request)
		let sheet = try await fetchSheet(request)
		let returnPath = parseReturnPath(request) ?? "/"
		
		let success: Bool
		
		do {
			try await request.db.transaction { db in
				let sheetID = try sheet.requireID()
				try await sheet.delete(on: db)
				
				try await storage.remove(sheetID: sheetID)
			}
			success = true
		} catch {
			success = false
		}
		
		let context = Context(username: user.username, sheet: try .init(sheet), return: returnPath, success: success)
		return try await request.view.render("Pages/delete", context)
	}
}
