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
		struct Context: Codable {
			var success: Bool = false
			var error: PostError? = nil
			var `return`: String
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
			let returnPath = parseReturnPath(req) ?? "/"
			return try await req.view.render("Pages/login", Context(return: returnPath))
		}
		
		routes.post { req -> View in
			let returnPath = parseReturnPath(req) ?? "/"
			
			do {
				guard let buffer = try? await req.body.collect(upTo: 1_000) else {
					throw PostError.unreadable
				}
				
				let decoder = URLEncodedFormDecoder()
				guard let credentials = try? decoder.decode(Credentials.self, from: buffer, headers: req.headers) else {
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
				
				return try await req.view.render("Pages/login", Context(success: true, return: returnPath))
			} catch let error as PostError {
				return try await req.view.render("Pages/login", Context(error: error, return: returnPath))
			} catch {
				return try await req.view.render("Pages/login", Context(error: .internal, return: returnPath))
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
