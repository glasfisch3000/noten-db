import Vapor

struct PageAttributes: Encodable {
	enum CodingKeys: CodingKey {
		case path
		case username
		case `return`
	}
	
	var path: String
	var user: User? = nil
	var returnPath: String? = nil
	
	init(_ request: Request, requireUser: Bool = false, requireReturn: Bool = false) throws {
		if requireUser {
			guard let user = request.auth.get(User.self) else {
				throw AuthError.missingLogin
			}
			
			self.user = user
		}
		
		if requireReturn {
			self.returnPath = try? request.query.get(String.self, at: "return")
		}
		
		self.path = request.url.path
	}
	
	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		
		try container.encode(self.path, forKey: .path)
		try container.encodeIfPresent(self.user?.username, forKey: .username)
		try container.encodeIfPresent(self.returnPath, forKey: .return)
	}
}
