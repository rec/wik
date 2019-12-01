TWIKIROOT=/var/www/twiki/trunk/core
TARGET= \
  jquery-all.js \
  jquery-all.css \
  jquery.debug.js \
  jquery.spinner.js

MINIFYJS=$(TWIKIROOT)/tools/minifyjs
MINIFYCSS=$(TWIKIROOT)/tools/minifycss


.SUFFIXES: .js .css

all: $(TARGET)
clean: 
	rm -f $(TARGET)

JS_SOURCES=\
  jquery.easing.js \
  jquery.hoverIntent.js \
  jquery.bgiframe.js \
  jquery.shrinkurls.js \
  jquery.blockUI.js \
  jquery.innerfade.js \
  jquery.dom.js \
  jquery.tooltip.js \
  jquery.nifty.js \
  jquery.treeview.js \
  jquery.treeview.async.js \
  jquery.twiki.js \
  jquery.tabpane.js

CSS_SOURCES=\
  jquery.nifty.css \
  jquery.twiki.css \
  jquery.tabpane.css \
  jquery.treeview.css

jquery-all.js: $(JS_SOURCES) Makefile $(MINIFYJS)
	@echo creating $@
	@$(MINIFYJS) $(JS_SOURCES) > $@

jquery-all.css: $(CSS_SOURCES) Makefile
	@echo creating $@
	@$(MINIFYCSS) $(CSS_SOURCES) > $@

%.js: %.uncompressed.js
	@echo creating $@ from $<
	@$(MINIFYJS) $< > $@

