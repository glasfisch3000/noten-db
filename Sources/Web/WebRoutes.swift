import Vapor
import Leaf
import Fluent

struct WebRoutes: RouteCollection {
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes
			.grouped(SessionAuthenticator())
			.group("login", configure: configureLogin(routes:))
		
		try routes
			.grouped(ErrorMiddleware())
			.group(SessionAuthenticator(strict: true)) { group in
				group.get("file", ":id", use: getFile(request:))
				try group.register(collection: StandardWebRoutes(storage: storage))
			}
	}
	
	func configureLogin(routes: RoutesBuilder) {
		struct Context: Encodable {
			var page: PageAttributes
			var success: Bool = false
			var error: PostError? = nil
		}
		
		enum PostError: String, Error, Codable {
			case unreadable
			case `internal`
			case wrong
		}
		
		struct Credentials: Codable {
			var username: String
			var password: String
		}
		
		@Sendable
		func parseReturnPath(_ request: Request) -> String? {
			try? request.query.get(String.self, at: "return")
		}
		
		routes.get { req -> View in
			let page = try PageAttributes(req, requireReturn: true)
			return try await req.view.render("Pages/login", Context(page: page))
		}
		
		routes.post { req -> View in
			let page = try PageAttributes(req, requireReturn: true)
			
			do {
				guard let credentials = try? await req.decodeBody(Credentials.self, as: .urlEncodedForm, maxBytes: 1_000) else {
					throw PostError.unreadable
				}
				
				guard let user = try await User
					.query(on: req.db)
					.filter(\.$username == credentials.username)
					.first() else {
					throw PostError.wrong
				}
				
				guard user.verify(password: credentials.password) else {
					throw PostError.wrong
				}
				
				req.session.authenticate(user)
				
				return try await req.view.render("Pages/login", Context(page: page, success: true))
			} catch let error as PostError {
				return try await req.view.render("Pages/login", Context(page: page, error: error))
			} catch {
				return try await req.view.render("Pages/login", Context(page: page, error: .internal))
			}
		}
	}
	
	func getFile(request: Request) async throws -> Response {
		guard let id = request.parameters.get("id", as: UUID.self) else {
			throw Abort(.notFound)
		}
		
		guard let (path, _) = try await storage.getInfo(sheetID: id) else {
			throw Abort(.notFound)
		}
		
		return try await request.fileio.asyncStreamFile(at: path.string, mediaType: .pdf, advancedETagComparison: true)
	}
}
