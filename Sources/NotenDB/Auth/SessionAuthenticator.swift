import Vapor
import Fluent

struct SessionAuthenticator: AsyncAuthenticator {
	var strict = false
	
	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		guard request.hasSession else {
			return try await next.respond(to: request)
		}
		
		guard let userID = request.session.authenticated(User.self) else {
			if strict {
				throw AuthError.invalidSession
			} else {
				return try await next.respond(to: request)
			}
		}
		
		guard let user = try await User.find(userID, on: request.db) else {
			throw AuthError.invalidSession
		}
		
		request.auth.login(user)
		return try await next.respond(to: request)
	}
}
