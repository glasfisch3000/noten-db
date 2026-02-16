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
			.grouped(SessionAuthenticator(strict: true))
			.register(collection: StandardWebRoutes(storage: storage))
	}
	
	func configureLogin(routes: RoutesBuilder) {
		struct Query: Codable {
			var `return`: String
		}
		
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
		
		routes.get { req -> View in
			let query = try? req.query.decode(Query.self)
			return try await req.view.render("Pages/login", Context(return: query?.return ?? "/"))
		}
		
		routes.post { req -> View in
			let query = try? req.query.decode(Query.self)
			let returnPath = query?.return ?? "/"
			
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
}
