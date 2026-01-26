import ArgumentParser

struct ServeCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "serve",
		abstract: "Run the HTTP server.",
		usage: """
			notendb serve [--help | --version]
			""",
		discussion: "",
		version: "0.0.0",
		shouldDisplay: true,
		helpNames: .shortAndLong
	)
	
	@Option(name: .shortAndLong)
	private var port: UInt16 = 8080
	
	@Option(name: .shortAndLong)
	private var hostname: String = "127.0.0.1"
	
	@Flag(exclusivity: .exclusive)
	private var migration: MigrationFlag?
	
	public func run() async throws {
		let args = ["serve"]
		
		try await withApplication(args) { app, _ in
			app.http.server.configuration.port = Int(self.port)
			app.http.server.configuration.hostname = self.hostname
			
			switch self.migration {
			case .migrate: try await app.autoMigrate()
			case .revert: try await app.autoRevert()
			case nil: break
			}
			
			try await app.execute()
		}
	}
}

extension ServeCommand {
	enum MigrationFlag: String, EnumerableFlag {
		case migrate
		case revert
	}
}
