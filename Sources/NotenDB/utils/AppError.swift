enum AppError: Error, CustomStringConvertible {
	enum ApplicationParameter: Sendable, CustomStringConvertible {
		case dbHostname, dbPort, dbUsername, dbPassword, dbName
		case sheetStorage
		
		var description: String {
			switch self {
			case .dbHostname: "postgres hostname"
			case .dbPort: "postgres port"
			case .dbUsername: "postgres username"
			case .dbPassword: "postgres password"
			case .dbName: "postgres database name"
			case .sheetStorage: "sheet storage path"
			}
		}
	}
	
	case missingEnvParameter(ApplicationParameter)
	case invalidEnvParameter(ApplicationParameter)
	case invalidInput(description: String)
	case modelNotFound(description: String)
	
	var description: String {
		switch self {
		case .missingEnvParameter(let applicationParameter):
			"Missing \(applicationParameter)"
		case .invalidEnvParameter(let applicationParameter):
			"Invalid \(applicationParameter)"
		case .invalidInput(let description):
			description
		case .modelNotFound(let description):
			description
		}
	}
}
