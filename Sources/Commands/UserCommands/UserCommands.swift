import ArgumentParser

struct UserCommands: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "user",
		abstract: "Configure users directly on the database.",
		usage: """
			notendb user list [-f <format>]
			notendb user create [-f <format>] -n <username> -p <password>
			notendb user get [-f <format>] (<username> | -id <userID>)
			notendb user set [-f <format>] (<username> | -id <userID>) [-u <new-username>] [-p <password>]
			notendb user delete [-f <format>] (<username> | -id <userID>)
			notendb user (--help | --version)
			""",
		discussion: "",
		version: "0.0.0",
		shouldDisplay: true,
		subcommands: [List.self, Create.self, Get.self, Set.self, Delete.self],
		helpNames: .shortAndLong
	)
}
