import ArgumentParser
import Foundation

enum OutputFormat: String, Sendable, Codable, ExpressibleByArgument {
	case json
	
	func format<T>(_ t: T) throws -> String where T: Encodable {
		switch self {
		case .json:
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
			
			let data = try encoder.encode(t)
			return String(decoding: data, as: UTF8.self)
		}
	}
}
