import NIOFileSystem
import Foundation
import ConvertPDF

final class FileStorage: Sendable {
	enum FileStorageError: Error {
		case fileExists(FilePath)
		
		/// Thrown when trying to access a nonexistent thumbnail file whose corresponding sheet file exists but cannot be converted.
		case unableToCreateThumbnail(PDFConversionError)
		case conversionError(PDFConversionError)
	}
	
	let fs = FileSystem.shared
	let sheetsDir: FilePath
	let thumbnailsDir: FilePath
	
	init(sheets: FilePath, thumbnails: FilePath) {
		self.sheetsDir = sheets
		self.thumbnailsDir = thumbnails
	}
	
	func listThumbnails() async throws -> [DirectoryEntry] {
		return try await fs.withDirectoryHandle(atPath: thumbnailsDir) { handle in
			try await Array(handle.listContents())
		}
	}
	
	func listSheets() async throws -> [DirectoryEntry] {
		return try await fs.withDirectoryHandle(atPath: sheetsDir) { handle in
			try await Array(handle.listContents())
		}
	}
	
	func getThumbnail(_ sheetID: Sheet.IDValue) async throws -> (FilePath, FileInfo)? {
		let dir = thumbnailsDir.appending(sheetID.uuidString)
		guard let info = try await fs.info(forFileAt: dir) else {
			return nil
		}
		
		return (dir, info)
	}
	
	func getSheet(_ sheetID: Sheet.IDValue) async throws -> (FilePath, FileInfo)? {
		let dir = sheetsDir.appending(sheetID.uuidString)
		guard let info = try await fs.info(forFileAt: dir) else {
			return nil
		}
		
		return (dir, info)
	}
	
	func getThumbnailOrConvert(_ sheetID: Sheet.IDValue) async throws -> FilePath? {
		let dir = thumbnailsDir.appending(sheetID.uuidString)
		if try await fs.info(forFileAt: dir) == nil {
			// try to create the missing thumbnail file, otherwise report it
			do {
				try createThumbnail(for: sheetID)
			} catch let error as PDFConversionError {
				switch error {
				case .cannotOpenDocument: return nil
				default: throw FileStorageError.unableToCreateThumbnail(error)
				}
			}
		}
		
		return dir
	}
	
	func remove(_ sheetID: Sheet.IDValue) async throws {
		let thumbnail = thumbnailsDir.appending(sheetID.uuidString)
		try await fs.removeItem(at: thumbnail)
		
		let sheet = sheetsDir.appending(sheetID.uuidString)
		try await fs.removeItem(at: sheet)
	}
	
	func create(_ sheetID: Sheet.IDValue, sheet: Data) async throws {
		let sheetFile = sheetsDir.appending(sheetID.uuidString)
		guard try await fs.info(forFileAt: sheetFile) == nil else {
			throw FileStorageError.fileExists(sheetFile)
		}
		
		let thumbnailFile = thumbnailsDir.appending(sheetID.uuidString)
		guard try await fs.info(forFileAt: thumbnailFile) == nil else {
			throw FileStorageError.fileExists(thumbnailFile)
		}
		
		do {
			try await sheet.write(toFileAt: sheetFile, options: .newFile(replaceExisting: false))
			try createThumbnail(for: sheetID)
		} catch {
			do { try await fs.removeItem(at: sheetFile) }
			do { try await fs.removeItem(at: thumbnailFile) }
			
			throw error
		}
	}
}

extension FileStorage {
	enum PDFConversionError: Error {
		case cannotOpenDocument
		case emptyDocument
		case cannotWriteImage
		case other(UInt32)
	}
	
	private func createThumbnail(for sheetID: Sheet.IDValue) throws {
		try thumbnailsDir.appending(sheetID.uuidString).withCString { thumbnail in
			try sheetsDir.appending(sheetID.uuidString).withCString { sheet in
				switch convertPDFFirstPageToPNG(sheet, thumbnail).rawValue {
				case 0: return // SUCCESS
				case 3: throw PDFConversionError.cannotOpenDocument // ERROR_CANNOT_OPEN_DOCUMENT
				case 5: throw PDFConversionError.emptyDocument // ERROR_NO_PAGES
				case 7: throw PDFConversionError.cannotWriteImage // ERROR_CANNOT_SAVE_FILE
				case let rawValue:
					// ERROR_CANNOT_CREATE_CONTEXT, ERROR_CANNOT_REGISTER_DOCUMENT_HANDLERS,
					// ERROR_CANNOT_COUNT_PAGES, ERROR_CANNOT_RENDER_PIXMAP
					throw PDFConversionError.other(rawValue)
				}
			}
		}
	}
}
