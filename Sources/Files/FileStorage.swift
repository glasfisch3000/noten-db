import NIOFileSystem

final class FileStorage: Sendable {
	let fs = FileSystem.shared
	let parentDir: FilePath
	
	init(parentDir: FilePath) {
		self.parentDir = parentDir
	}
	
	func list() async throws -> [DirectoryEntry] {
		return try await fs.withDirectoryHandle(atPath: parentDir) { handle in
			try await Array(handle.listContents())
		}
	}
	
	func getInfo(sheetID: Sheet.IDValue) async throws -> (FilePath, FileInfo)? {
		let dir = parentDir.appending(sheetID.uuidString)
		guard let info = try await fs.info(forFileAt: dir) else {
			return nil
		}
		
		return (dir, info)
	}
	
	func read(sheetID: Sheet.IDValue) async throws -> FileChunks? {
		let dir = parentDir.appending(sheetID.uuidString)
		if try await fs.info(forFileAt: dir) == nil {
			return nil
		}
		
		return try await fs.withFileHandle(forReadingAt: dir) { handle in
			handle.readChunks()
		}
	}
	
	func remove(sheetID: Sheet.IDValue) async throws {
		let dir = parentDir.appending(sheetID.uuidString)
		try await fs.removeItem(at: dir)
	}
}
