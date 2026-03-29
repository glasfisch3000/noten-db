import Vapor
import Leaf
import Fluent
import NIOCore

struct AuthenticatedRoutes: RouteCollection {
	enum RequestError: Error {
		case invalidFormat
	}
	
	var storage: FileStorage
	
	func boot(routes: any RoutesBuilder) throws {
		routes.get(use: index(request:))
		
		routes.get("upload", use: upload(request:))
		routes.on(.POST, "upload", body: .stream, use: postUpload(request:))
		
		try routes
			.grouped(":id")
			.register(collection: ItemRoutes(storage: storage))
		
		routes.get("change-password", use: getChangePassword(request:))
		routes.on(.POST, "change-password", body: .stream, use: postChangePassword(request:))
		
		routes.get("search", use: getSearch(request:))
	}
}

extension AuthenticatedRoutes {
	func index(request: Request) async throws -> View {
		enum SearchError: String, Error, Encodable {
			case empty
			case tooLarge
			case noMatches
		}
		
		struct Context: Encodable {
			struct Search: Encodable {
				var string: String
				var success: Bool
				var error: SearchError?
			}
			
			var user: UserDTO
			var sheets: [SheetDTO]
			
			var search: Search?
		}
		
		let user = try request.auth.require(User.self)
		let searchString = try? request.query.get(String.self, at: "search")
		
		if let searchString {
			do {
				if searchString.count > 100 {
					throw SearchError.tooLarge
				}
				
				guard let results = try await search(searchString, on: request.db) else {
					throw SearchError.empty
				}
				
				if results.isEmpty {
					throw SearchError.noMatches
				}
				
				let dtos = try results.map(SheetDTO.init(_:))
				
				let context = Context(
					user: try UserDTO(user),
					sheets: dtos,
					search: .init(string: searchString, success: true)
				)
				return try await request.view.render("Pages/index", context)
			} catch let error as SearchError {
				let context = Context(
					user: try UserDTO(user),
					sheets: [],
					search: .init(string: searchString, success: false, error: error)
				)
				return try await request.view.render("Pages/index", context)
			}
		} else {
			let sheets = try await Sheet
				.query(on: request.db)
				.with(\.$createdBy)
				.all()
			
			let context = Context(
				user: try UserDTO(user),
				sheets: try sheets.map(SheetDTO.init(_:)),
			)
			
			return try await request.view.render("Pages/index", context)
		}
	}
	
	func upload(request: Request) async throws -> View {
		let user = try request.auth.require(User.self)
		guard user.canUpload else {
			throw Abort(.forbidden)
		}
		
		return try await request.view.render("Pages/upload", ["user": try UserDTO(user)])
	}
	
	func postUpload(request: Request) async throws -> View {
		struct UploadData: Codable {
			var title: String
			var composer: String?
			var arranger: String?
			var file: Data
			
			init(from decoder: any Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				
				self.title = try container.decode(String.self, forKey: .title)
				if title.isEmpty { throw RequestError.invalidFormat }
				
				self.composer = try container.decodeIfPresent(String.self, forKey: .composer)
				if let composer, composer.isEmpty { self.composer = nil }
				
				self.arranger = try container.decodeIfPresent(String.self, forKey: .arranger)
				if let arranger, arranger.isEmpty { self.arranger = nil }
				
				self.file = try container.decode(Data.self, forKey: .file)
			}
		}
		
		struct Context: Encodable {
			enum PostError: String, Error, Codable {
				case unreadable
				case tooLarge
				case `internal`
			}
			
			var user: UserDTO
			
			var success: Bool
			var error: PostError? = nil
		}
		
		let user = try request.auth.require(User.self)
		guard user.canUpload else {
			throw Abort(.forbidden)
		}
		
		do {
			// collect data
			let uploadData = try await request.decodeBody(UploadData.self, as: .formData, maxBytes: 15_000_000) // 15MB
			
			// try to store data in database and file at once. if one fails, return an error
			try await request.db.transaction { db in
				let sheet = Sheet(
					title: uploadData.title,
					composer: uploadData.composer,
					arranger: uploadData.arranger,
					createdBy: try user.requireID()
				)
				try await sheet.create(on: db)
				
				try await storage.create(try sheet.requireID(), sheet: uploadData.file)
			}
			
			let context = Context(user: try UserDTO(user), success: true)
			return try await request.view.render("Pages/upload", context)
		} catch _ as NIOTooManyBytesError {
			let context = Context(user: try UserDTO(user), success: false, error: .tooLarge)
			return try await request.view.render("Pages/upload", context)
		} catch _ as Abort, _ as DecodingError {
			let context = Context(user: try UserDTO(user), success: false, error: .unreadable)
			return try await request.view.render("Pages/upload", context)
		} catch {
			let context = Context(user: try UserDTO(user), success: false, error: .internal)
			return try await request.view.render("Pages/upload", context)
		}
	}
	
	func getChangePassword(request: Request) async throws -> View {
		let user = try request.auth.require(User.self)
		return try await request.view.render("Pages/change-password", ["user": try UserDTO(user)])
	}
	
	func postChangePassword(request: Request) async throws -> View {
		enum PostError: String, Codable {
			case unreadable
			case `internal`
			case wrong
			case invalid
			case noMatch
		}
		
		struct Context: Encodable {
			var user: UserDTO
			var success: Bool
			var error: PostError? = nil
		}
		
		struct Query: Codable {
			enum CodingKeys: String, CodingKey {
				case currentPassword = "current-password"
				case newPassword = "new-password"
				case newPasswordRepeat = "new-password-repeat"
			}
			
			var currentPassword: String
			var newPassword: String
			var newPasswordRepeat: String
		}
		
		let user = try request.auth.require(User.self)
		
		do {
			// collect data
			let queryData = try await request.decodeBody(Query.self, as: .urlEncodedForm, maxBytes: 2_000) // 2KB
			
			guard user.verify(password: queryData.currentPassword) else {
				let context = Context(user: try UserDTO(user), success: false, error: .wrong)
				return try await request.view.render("Pages/change-password", context)
			}
			
			guard queryData.newPassword == queryData.newPasswordRepeat else {
				let context = Context(user: try UserDTO(user), success: false, error: .noMatch)
				return try await request.view.render("Pages/change-password", context)
			}
			
			if queryData.newPassword.isEmpty {
				let context = Context(user: try UserDTO(user), success: false, error: .invalid)
				return try await request.view.render("Pages/change-password", context)
			}
			
			user.password = User.hashPassword(queryData.newPassword, salt: user.salt)
			try await user.update(on: request.db)
			
			let context = Context(user: try UserDTO(user), success: true)
			return try await request.view.render("Pages/change-password", context)
		} catch _ as NIOTooManyBytesError, _ as Abort, _ as DecodingError {
			let context = Context(user: try UserDTO(user), success: false, error: .unreadable)
			return try await request.view.render("Pages/change-password", context)
		} catch {
			let context = Context(user: try UserDTO(user), success: false, error: .internal)
			return try await request.view.render("Pages/change-password", context)
		}
	}
	
	func getSearch(request: Request) async throws -> [SheetDTO] {
		let searchString = try request.query
			.get(String.self, at: "search")
		
		if searchString.count > 100 {
			throw RequestError.invalidFormat
		}
		
		let results = try await search(searchString, on: request.db) ?? []
		return try results.map(SheetDTO.init(_:))
	}
	
	func search(_ search: String, on db: any Database) async throws -> [Sheet]? {
		struct Match: Comparable {
			var sheet: Sheet
			var score: Int
			
			static func < (lhs: Match, rhs: Match) -> Bool {
				lhs.score < rhs.score
			}
			
			static func == (lhs: Match, rhs: Match) -> Bool {
				lhs.score == rhs.score
			}
		}
		
		let tokens = tokenize(search)
		if tokens.isEmpty {
			return nil
		}
		
		let allSheets = try await Sheet.query(on: db).all()
		var matches = [Match]()
		
		sheet_loop: for sheet in allSheets {
			var bestMatch = 0
			var tokenIndex = 0
			
			while tokenIndex < tokens.count {
				guard let match = findMatch(tokens, index: &tokenIndex, sheet: sheet) else {
					continue sheet_loop
				}
				
				bestMatch = max(bestMatch, match)
			}
			
			matches.append(Match(sheet: sheet, score: bestMatch))
		}
		
		return matches.sorted().map(\.sheet)
	}
	
	// returns the length of the best match
	func findMatch(_ tokens: [Substring], index tokenIndex: inout Int, sheet: Sheet) -> Int? {
		enum Match {
			case title(start: Int, end: Int)
			case composer(start: Int, end: Int)
			case arranger(start: Int, end: Int)
			
			var length: Int {
				switch self {
				case .title(let start, let end): end - start
				case .composer(let start, let end): end - start
				case .arranger(let start, let end): end - start
				}
			}
		}
		
		// tokenize the sheet's attributes
		// treat nonexistent composer/arranger as empty strings
		let title = tokenize(sheet.title)
		let composer = sheet.composer.map(tokenize(_:)) ?? []
		let arranger = sheet.arranger.map(tokenize(_:)) ?? []
		
		var matches = [Match]()
		var bestMatchLength = 1
		
		// add initial matches
		matches += title
			.indexed()
			.compactMap { index, element in
				guard element.starts(with: tokens[tokenIndex]) else {
					return nil
				}
				
				return Match.title(start: index, end: index+1)
			}
		matches += composer
			.indexed()
			.compactMap { index, element in
				guard element.starts(with: tokens[tokenIndex]) else {
					return nil
				}
				
				return Match.composer(start: index, end: index+1)
			}
		matches += arranger
			.indexed()
			.compactMap { index, element in
				guard element.starts(with: tokens[tokenIndex]) else {
					return nil
				}
				
				return Match.arranger(start: index, end: index+1)
			}
		
		// if there are no intial matches, abort
		if matches.isEmpty {
			return nil
		}
		
		// start with the next token. the current one has been checked already
		tokenIndex += 1
		while tokenIndex < tokens.count {
			for (index, match) in matches.indexed() {
				// check if each match can be expanded to the next token
				switch match {
				case .title(let start, let end):
					guard end < title.count else { continue }
					guard title[end].starts(with: tokens[tokenIndex]) else { continue }
					matches[index] = .title(start: start, end: end+1)
				case .composer(let start, let end):
					guard end < composer.count else { continue }
					guard composer[end].starts(with: tokens[tokenIndex]) else { continue }
					matches[index] = .composer(start: start, end: end+1)
				case .arranger(let start, let end):
					guard end < arranger.count else { continue }
					guard arranger[end].starts(with: tokens[tokenIndex]) else { continue }
					matches[index] = .arranger(start: start, end: end+1)
				}
			}
			
			// remove outdated matches
			matches.removeAll { $0.length <= bestMatchLength }
			
			// if there are no matches left, return
			if matches.isEmpty {
				return bestMatchLength
			}
			
			tokenIndex += 1
			bestMatchLength += 1
		}
		
		return bestMatchLength
	}
	
	func tokenize(_ string: String) -> [Substring] {
		string
			.lowercased()
			.split(separator: /[\n\t ,;.…:_\-–—~()\[\]{}\/\\|"„““”''‘’´`+*#?¿!¡&%$§<>]/)
			.filter { !$0.isEmpty }
	}
}
