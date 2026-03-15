import ArgumentParser

@main
struct NotenDB: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "zitate",
		usage: """
			notendb <subcommand>
			notendb (--help | --version)
			""",
		version: "0.0.0",
		subcommands: [ServeCommand.self, RoutesCommand.self, MigrateCommand.self, UserCommands.self, FileCommands.self],
		helpNames: .shortAndLong
	)
}
