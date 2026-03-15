import Leaf

struct AttributeTag: LeafTag {
	enum Attribute: String {
		case path
		case `return`
	}
	
	enum AttributeTagError: Error {
		case missingParameter
		case invalidParameterType
		case invalidParameter(String)
		case noRequestData
	}
	
	func render(_ ctx: LeafContext) throws(AttributeTagError) -> LeafData {
		guard let request = ctx.request else {
			throw AttributeTagError.noRequestData
		}
		
		guard let param0 = ctx.parameters.first else {
			throw AttributeTagError.missingParameter
		}
		guard let param0String = param0.string else {
			throw AttributeTagError.invalidParameterType
		}
		guard let attribute = Attribute(rawValue: param0String) else {
			throw AttributeTagError.invalidParameter(param0String)
		}
		
		var value = switch attribute {
		case .path: request.url.path + "?" + (request.url.query ?? "")
		case .return: (try? request.query.get(String.self, at: "return")) ?? "/"
		}
		
		if ctx.parameters.count > 1 {
			let params = ctx.parameters[1...]
			
			if params.contains(where: { $0.string == "queryEncoding" }) {
				value = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
			}
		}
		
		return .string(value)
	}
}
