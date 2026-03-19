#import <mupdf/fitz.h>
#pragma once

typedef enum convert_status {
	SUCCESS,
	ERROR_CANNOT_CREATE_CONTEXT,
	ERROR_CANNOT_REGISTER_DOCUMENT_HANDLERS,
	ERROR_CANNOT_OPEN_DOCUMENT,
	ERROR_CANNOT_COUNT_PAGES,
	ERROR_NO_PAGES,
	ERROR_CANNOT_RENDER_PIXMAP,
	ERROR_CANNOT_SAVE_FILE,
} ConvertStatus;

ConvertStatus convertPDFFirstPageToPNG(const char input[], const char output[]);
