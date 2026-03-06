import Vapor
import Leaf
import Fluent

struct WebRoutes: RouteCollection {
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes
			.grouped(ErrorMiddleware())
			.group(SessionAuthenticator()) {
				$0.get("login", use: getLogin(request:))
				$0.post("login", use: postLogin(request:))
				$0.get("logout", use: getLogout(request:))
			}
		
		try routes
			.grouped(ErrorMiddleware())
			.group(SessionAuthenticator(strict: true)) { group in
				group.get("file", ":id", use: getFile(request:))
				try group.register(collection: StandardWebRoutes(storage: storage))
			}
	}
	
	func getLogin(request: Request) async throws -> View {
		try await request.view.render("Pages/login")
	}
	
	func postLogin(request: Request) async throws -> View {
		enum PostError: String, Error, Codable {
			case unreadable
			case `internal`
			case wrong
		}
		
		struct Credentials: Codable {
			var username: String
			var password: String
		}
		
		do {
			guard let credentials = try? await request.decodeBody(Credentials.self, as: .urlEncodedForm, maxBytes: 1_000) else {
				throw PostError.unreadable
			}
			
			guard let user = try await User
				.query(on: request.db)
				.filter(\.$username == credentials.username)
				.first() else {
				throw PostError.wrong
			}
			
			guard user.verify(password: credentials.password) else {
				throw PostError.wrong
			}
			
			request.session.authenticate(user)
			
			return try await request.view.render("Pages/login", ["success": true])
		} catch let error as PostError {
			return try await request.view.render("Pages/login", ["error": error])
		} catch {
			return try await request.view.render("Pages/login", ["error": PostError.internal])
		}
	}
	
	func getLogout(request: Request) async throws -> View {
		request.session.destroy()
		request.auth.logout(User.self)
		return try await request.view.render("Pages/logout")
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
