import Vapor

struct WebRoutes: RouteCollection {
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		try routes
			.grouped(ErrorMiddleware())
			.grouped(SessionAuthenticator())
			.register(collection: LoginRoutes())
		
		try routes
			.grouped(ErrorMiddleware())
			.grouped(SessionAuthenticator(strict: true))
			.register(collection: AuthenticatedRoutes(storage: storage))
	}
}
