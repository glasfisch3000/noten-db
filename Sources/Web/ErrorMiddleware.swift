import Vapor
import Leaf

struct ErrorMiddleware: AsyncMiddleware {
	func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
		do {
			return try await next.respond(to: request)
		} catch _ as AuthError {
			let query = request.url
				.string
				.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
				.flatMap { "?return=\($0)" }
			
			return request.redirect(to: "login\(query ?? "")")
		}
	}
}
