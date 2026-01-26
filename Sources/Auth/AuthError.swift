enum AuthError: Error, Hashable, Codable {
	case invalidLoginData
	case invalidSession
	case missingLogin
}
