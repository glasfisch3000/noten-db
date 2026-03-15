import Vapor
import Fluent

struct CredentialAuthenticator: AsyncBasicAuthenticator {
	init() { }
    
	func authenticate(basic: BasicAuthorization, for request: Request) async throws {
		guard let user = try await User.query(on: request.db)
			.filter(\.$username == basic.username)
			.first() else {
			throw AuthError.invalidLoginData
		}
		
		guard user.verify(password: basic.password) else {
			throw AuthError.invalidLoginData
		}
		
		request.auth.login(user)
	}
}
