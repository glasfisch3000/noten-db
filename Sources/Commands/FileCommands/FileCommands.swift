import ArgumentParser

struct FileCommands: AsyncParsableCommand {
	static let configuration = CommandConfiguration(
		commandName: "file",
		abstract: "Work with the sheet file storage.",
		usage: """
			notendb file list [-f <format>]
			notendb file get [-f <format>] <sheetID>
			notendb file (--help | --version)
			""",
		discussion: "",
		version: "0.0.0",
		shouldDisplay: true,
		subcommands: [List.self, Get.self],
		helpNames: .shortAndLong
	)
}
