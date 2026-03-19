// Convert a pdf's first page to a PNG image

#include <stdio.h>
#include <stdlib.h>

#include "ConvertPDF/ConvertPDF.h"

ConvertStatus convertPDFFirstPageToPNG(const char input[], const char output[]) {
	fz_context *ctx;
	fz_document *doc;
	fz_pixmap *pix;
	int pageCount;
	
	// create context
	ctx = fz_new_context(NULL, NULL, FZ_STORE_UNLIMITED);
	if (!ctx) {
		return ERROR_CANNOT_CREATE_CONTEXT;
	}
	
	// register the default file types to handle
	fz_try(ctx)
		fz_register_document_handlers(ctx);
	fz_catch(ctx) {
		fz_report_error(ctx);
		fz_drop_context(ctx);
		return ERROR_CANNOT_REGISTER_DOCUMENT_HANDLERS;
	}
	
	// open the document
	fz_try(ctx)
		doc = fz_open_document(ctx, input);
	fz_catch(ctx) {
		fz_report_error(ctx);
		fz_drop_context(ctx);
		return ERROR_CANNOT_OPEN_DOCUMENT;
	}
	
	// count the number of pages
	fz_try(ctx)
		pageCount = fz_count_pages(ctx, doc);
	fz_catch(ctx) {
		fz_report_error(ctx);
		fz_drop_document(ctx, doc);
		fz_drop_context(ctx);
		return ERROR_CANNOT_COUNT_PAGES;
	}
	
	// abort if there are no pages
	if (pageCount < 1) {
		fz_drop_document(ctx, doc);
		fz_drop_context(ctx);
		return ERROR_NO_PAGES;
	}
	
	// render the page to an rgb pixmap
	fz_try(ctx)
		pix = fz_new_pixmap_from_page_number(ctx, doc, 0, fz_identity, fz_device_rgb(ctx), 0);
	fz_catch(ctx) {
		fz_report_error(ctx);
		fz_drop_document(ctx, doc);
		fz_drop_context(ctx);
		return ERROR_CANNOT_RENDER_PIXMAP;
	}
	
	fz_try(ctx)
		fz_save_pixmap_as_png(ctx, pix, output);
	fz_catch(ctx) {
		fz_report_error(ctx);
		fz_drop_pixmap(ctx, pix);
		fz_drop_document(ctx, doc);
		fz_drop_context(ctx);
		return ERROR_CANNOT_SAVE_FILE;
	}
	
	fz_drop_pixmap(ctx, pix);
	fz_drop_document(ctx, doc);
	fz_drop_context(ctx);
	return SUCCESS;
}
