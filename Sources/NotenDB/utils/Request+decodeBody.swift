import Vapor

extension Request {
	internal func decodeBody<T: Decodable>(_ t: T.Type = T.self, as type: HTTPMediaType, maxBytes: Int) async throws -> T {
		let buffer = if let data = self.body.data {
			data
		} else {
			try await self.body.collect(upTo: maxBytes)
		}
		
		let decoder = try ContentConfiguration.global.requireDecoder(for: type)
		return try decoder.decode(T.self, from: buffer, headers: self.headers)
	}
}
