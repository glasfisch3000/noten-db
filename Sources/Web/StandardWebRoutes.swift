import Vapor
import Leaf
import Fluent

struct StandardWebRoutes: RouteCollection {
	enum RequestError: Error {
		case invalidPagingSize(UInt)
	}
	
	func boot(routes: any RoutesBuilder) throws {
		routes.get(use: index(request:))
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
}
