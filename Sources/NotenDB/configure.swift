import Vapor
import Fluent
import FluentPostgresDriver
import Leaf
import NIOFileSystem

#if DEBUG
fileprivate let ENV = Environment.development
#else
fileprivate let ENV = Environment.production
#endif

internal func configureApplication(_ args: [String] = []) async throws -> (Application, FileStorage) {
	var env = ENV
	env.commandInput.arguments = args
	
	try LoggingSystem.bootstrap(from: &env)
	let app = try await Application.make(env)
	
	do {
		guard let sheetStorage = Environment.get("NOTEN_DB_SHEET_STORAGE") else {
			throw AppError.missingEnvParameter(.sheetStorage)
		}
		guard let thumbnailStorage = Environment.get("NOTEN_DB_THUMBNAIL_STORAGE") else {
			throw AppError.missingEnvParameter(.thumbnailStorage)
		}
		
		let storage = FileStorage(sheets: FilePath(sheetStorage), thumbnails: FilePath(thumbnailStorage))
		
		guard let hostname = Environment.get("NOTEN_DB_HOSTNAME") else {
			throw AppError.missingEnvParameter(.dbHostname)
		}
		
		guard let portString = Environment.get("NOTEN_DB_PORT") else {
			throw AppError.missingEnvParameter(.dbPort)
		}
		guard let port = Int(portString) else {
			throw AppError.invalidEnvParameter(.dbPort)
		}
		
		guard let username = Environment.get("NOTEN_DB_USERNAME") else {
			throw AppError.missingEnvParameter(.dbUsername)
		}
		
		guard let password = Environment.get("NOTEN_DB_PASSWORD") else {
			throw AppError.missingEnvParameter(.dbPassword)
		}
		
		guard let database = Environment.get("NOTEN_DB_DATABASE") else {
			throw AppError.missingEnvParameter(.dbName)
		}
		
		app.databases.use(
			.postgres(configuration: .init(
				hostname: hostname,
				port: port,
				username: username,
				password: password,
				database: database,
				tls: .prefer(try .init(configuration: .clientDefault))
			)),
			as: .psql
		)
		
		app.migrations.add(User.CreateUserMigration())
		app.migrations.add(Sheet.CreateSheetMigration())
		app.migrations.add(Sheet.DeleteYearMigration())
		app.migrations.add(Sheet.AddSoftDeleteMigration())
		
		// add leaf rendering
		app.views.use(.leaf)
		app.leaf.tags["attribute"] = AttributeTag()
		
		// serve files from the Public directory
		let fileMiddleware = FileMiddleware(publicDirectory: app.directory.publicDirectory, advancedETagComparison: true, cachePolicy: .noCache)
		app.middleware.use(fileMiddleware)
		
		app.sessions.configuration.cookieFactory = { sessionID in
			HTTPCookies.Value(
				string: sessionID.string,
				expires: .now + 60*60*24*7, // one week
				maxAge: nil,
				domain: nil,
				path: "/",
				isSecure: false,
				isHTTPOnly: false,
				sameSite: .strict
			)
		}
		
		app.middleware.use(app.sessions.middleware)
		app.sessions.use(.memory)
		
		try app.routes
			.register(collection: WebRoutes(storage: storage))
		
		return (app, storage)
	} catch {
		try? await app.asyncShutdown()
		throw error
	}
}

@discardableResult
internal func withApplication<T>(_ args: [String] = [], callback: (Application, FileStorage) async throws -> T) async throws -> T {
	let (app, storage) = try await configureApplication(args)
	
	do {
		let t = try await callback(app, storage)
		try await app.asyncShutdown()
		return t
	} catch {
		app.logger.report(error: error)
		try? await app.asyncShutdown()
		throw error
	}
}

@discardableResult
internal func withApplicationDBTransaction<T: Sendable>(_ args: [String] = [], callback: @Sendable @escaping (Database, FileStorage) async throws -> T) async throws -> T {
	let (app, storage) = try await configureApplication(args)
	
	do {
		let t = try await app.db.transaction {
			try await callback($0, storage)
		}
		try await app.asyncShutdown()
		return t
	} catch {
		app.logger.report(error: error)
		try? await app.asyncShutdown()
		throw error
	}
}
