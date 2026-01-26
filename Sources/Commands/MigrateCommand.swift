import ArgumentParser

struct MigrateCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "migrate",
		abstract: "Apply or revert database migrations.",
		usage: """
			notendb migrate [--revert]
			notendb migrate (--help | --version)
			""",
		discussion: "",
		version: "0.0.0",
		shouldDisplay: true,
		helpNames: .shortAndLong
	)
	
	@Flag(name: .shortAndLong, help: "Revert migrations instead of applying them.")
	private var revert = false
	
	public func run() async throws {
		let args = ["migrate"] + (revert ? ["--revert"] : [])
		
		try await withApplication(args) { app, _ in
			try await app.execute()
		}
	}
}
