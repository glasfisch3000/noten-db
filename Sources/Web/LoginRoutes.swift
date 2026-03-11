import Vapor
import Leaf
import Fluent

struct LoginRoutes: RouteCollection {
	func boot(routes: any RoutesBuilder) {
		routes.get("login", use: getLogin(request:))
		routes.on(.POST, "login", body: .stream, use: postLogin(request:))
		
		routes.get("logout", use: getLogout(request:))
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
}
