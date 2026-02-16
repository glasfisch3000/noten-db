import Vapor
import Leaf
import Fluent
import NIOCore

struct StandardWebRoutes: RouteCollection {
	enum RequestError: Error {
		case invalidPagingSize(UInt)
		case tooLarge
	}
	
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes.get(use: index(request:))
		
		routes.get("upload", use: upload(request:))
		routes.on(.POST, "upload", body: .stream, use: postUpload(request:))
	}
	
	func index(request: Request) async throws -> View {
		struct Context: Codable {
			struct Sheet: Codable {
				struct Creator: Codable {
					var username: String
				}
				
				var title: String
				var composer: String?
				var year: Int?
				var creator: Creator
			}
			
			var username: String
			var sheets: [Sheet]
			
			var page: UInt
			var pageCount: UInt
			var pageSize: UInt
			var total: UInt
		}
		
		struct Query: Codable {
			var page: UInt?
			var size: UInt?
		}
		
		guard let user = request.auth.get(User.self) else {
			throw AuthError.missingLogin
		}
		
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
			sheets: sheets.items.map {
				Context.Sheet(
					title: $0.title,
					composer: $0.composer,
					creator: Context.Sheet.Creator(
						username: $0.createdBy.username
					)
				)
			},
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
		
		guard let user = request.auth.get(User.self) else {
			throw AuthError.missingLogin
		}
		let context = Context(username: user.username)
		
		return try await request.view.render("Pages/upload", context)
	}
	
	func postUpload(request: Request) async throws -> View {
		struct UploadData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			var year: Int?
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
		guard let user = request.auth.get(User.self) else {
			throw AuthError.missingLogin
		}
		
		// collect data
		let uploadData: UploadData
		do {
			let buffer = if let data = request.body.data {
				data
			} else {
				try await request.body.collect(upTo: 10_000_000) // max 10MB
			}
			
			let decoder = try ContentConfiguration.global.requireDecoder(for: .formData)
			uploadData = try decoder.decode(UploadData.self, from: buffer, headers: request.headers)
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
					year: uploadData.year,
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
}
