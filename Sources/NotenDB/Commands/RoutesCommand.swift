import ArgumentParser

struct RoutesCommand: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "routes",
		abstract: "Show HTTP server routes.",
		usage: """
		   notendb routes [--help | --version]
		   """,
		discussion: "",
		version: "0.0.0",
		shouldDisplay: true,
		helpNames: .shortAndLong
	)
	
	public func run() async throws {
		let args = ["routes"]
		
		try await withApplication(args) { app, _ in
			try await app.execute()
		}
	}
}
