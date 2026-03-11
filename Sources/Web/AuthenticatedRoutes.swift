import Vapor
import Leaf
import Fluent
import NIOCore

struct AuthenticatedRoutes: RouteCollection {
	enum RequestError: Error {
		case invalidPagingSize(UInt)
		case invalidFormat
	}
	
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes.get(use: index(request:))
		
		routes.get("upload", use: upload(request:))
		routes.on(.POST, "upload", body: .stream, use: postUpload(request:))
		
		try routes
			.grouped(":id")
			.register(collection: ItemRoutes(storage: storage))
		
		routes.get("change-password", use: getChangePassword(request:))
		routes.on(.POST, "change-password", body: .stream, use: postChangePassword(request:))
	}
}

extension AuthenticatedRoutes {
	func index(request: Request) async throws -> View {
		struct Context: Encodable {
			var username: String
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
		
		let user = try request.auth.require(User.self)
		
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
			pageNumber: UInt(sheets.metadata.page),
			pageCount: UInt(sheets.metadata.pageCount),
			pageSize: UInt(sheets.metadata.per),
			total: UInt(sheets.metadata.total)
		)
		
		return try await request.view.render("Pages/index", context)
	}
	
	func upload(request: Request) async throws -> View {
		let user = try request.auth.require(User.self)
		return try await request.view.render("Pages/upload", ["username": user.username])
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
			
			var username: String
			
			var success: Bool
			var error: PostError? = nil
		}
		
		let user = try request.auth.require(User.self)
		
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
					createdBy: try user.requireID()
				)
				try await sheet.create(on: db)
				
				try await storage.create(sheetID: try sheet.requireID(), contents: uploadData.file)
			}
			
			let context = Context(username: user.username, success: true)
			return try await request.view.render("Pages/upload", context)
		} catch _ as NIOTooManyBytesError {
			let context = Context(username: user.username, success: false, error: .tooLarge)
			return try await request.view.render("Pages/upload", context)
		} catch _ as Abort, _ as DecodingError {
			let context = Context(username: user.username, success: false, error: .unreadable)
			return try await request.view.render("Pages/upload", context)
		} catch {
			let context = Context(username: user.username, success: false, error: .internal)
			return try await request.view.render("Pages/upload", context)
		}
	}
	
	func getChangePassword(request: Request) async throws -> View {
		let user = try request.auth.require(User.self)
		return try await request.view.render("Pages/change-password", ["username": user.username])
	}
	
	func postChangePassword(request: Request) async throws -> View {
		enum PostError: String, Codable {
			case unreadable
			case `internal`
			case wrong
			case invalid
			case noMatch
		}
		
		struct Context: Encodable {
			var username: String
			var success: Bool
			var error: PostError? = nil
		}
		
		struct Query: Codable {
			enum CodingKeys: String, CodingKey {
				case currentPassword = "current-password"
				case newPassword = "new-password"
				case newPasswordRepeat = "new-password-repeat"
			}
			
			var currentPassword: String
			var newPassword: String
			var newPasswordRepeat: String
		}
		
		let user = try request.auth.require(User.self)
		
		do {
			// collect data
			let queryData = try await request.decodeBody(Query.self, as: .urlEncodedForm, maxBytes: 2_000) // 2KB
			
			guard user.verify(password: queryData.currentPassword) else {
				let context = Context(username: user.username, success: false, error: .wrong)
				return try await request.view.render("Pages/change-password", context)
			}
			
			guard queryData.newPassword == queryData.newPasswordRepeat else {
				let context = Context(username: user.username, success: false, error: .noMatch)
				return try await request.view.render("Pages/change-password", context)
			}
			
			if queryData.newPassword.isEmpty {
				let context = Context(username: user.username, success: false, error: .invalid)
				return try await request.view.render("Pages/change-password", context)
			}
			
			user.password = User.hashPassword(queryData.newPassword, salt: user.salt)
			try await user.update(on: request.db)
			
			let context = Context(username: user.username, success: true)
			return try await request.view.render("Pages/change-password", context)
		} catch _ as NIOTooManyBytesError, _ as Abort, _ as DecodingError {
			let context = Context(username: user.username, success: false, error: .unreadable)
			return try await request.view.render("Pages/change-password", context)
		} catch {
			let context = Context(username: user.username, success: false, error: .internal)
			return try await request.view.render("Pages/change-password", context)
		}
	}
}
