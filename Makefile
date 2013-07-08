#
# Makefile
#
# Makefile for the CSEtella project
# Itai Rosenberger (itairos@cs.washington.edu)
#
# CSEP552 Assignment #3
# http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
#

TOOLS = tools
OUTPUT = bin

# Code
SOURCE_DIR = src
SOURCE_OUTPUT = $(OUTPUT)/src
CC = $(TOOLS)/node_modules/coffee-script/bin/coffee
SOURCE_COFFEE_FILES := $(wildcard $(SOURCE_DIR)/*.coffee)
SOURCE_JS_FILES = $(SOURCE_COFFEE_FILES:.coffee=.js)

# Test
TEST_DIR = test
TEST_OUTPUT = $(OUTPUT)/test
MOCHA = $(TOOLS)/node_modules/mocha/bin/mocha
TEST_COFFEE_FILES := $(wildcard $(TEST_DIR)/*.coffee)
TEST_JS_FILES = $(TEST_COFFEE_FILES:.coffee=.js)

# Website
WEB_ROOT = $(OUTPUT)/web
WEB_PUBLIC = $(WEB_ROOT)/public

# Submit
SUBMIT_FILE = ex3.tar.bz2
SUBMIT_EXCLUDE = --exclude='.*'
SUBMIT_INCLUDE = ex3/src ex3/test ex3/Makefile ex3/install-nodejs.sh


# Code Rules

$(SOURCE_DIR)/%.js: $(SOURCE_DIR)/%.coffee
	$(CC) --output $(SOURCE_OUTPUT) --compile $<

$(SOURCE_OUTPUT)/%.json: $(SOURCE_DIR)/%.json
	cp $< $@

csetella: tools $(SOURCE_JS_FILES)

clean:
	rm -rf $(OUTPUT)

install: csetella $(SOURCE_OUTPUT)/package.json $(SOURCE_OUTPUT)/config.json
	cd $(SOURCE_OUTPUT);\
	npm install;

start: install web
	cd $(SOURCE_OUTPUT);\
	../../tools/node_modules/forever/bin/forever start csetella-node.js

stop:
	cd $(SOURCE_OUTPUT);\
	../../tools/node_modules/forever/bin/forever stop csetella-node.js

restart:
	cd $(SOURCE_OUTPUT);\
	../../tools/node_modules/forever/bin/forever restart csetella-node.js

# Test Rules

$(TEST_DIR)/%.js: $(TEST_DIR)/%.coffee
	$(CC) -o $(TEST_OUTPUT) -c $<

$(TEST_OUTPUT)/%.json: $(TEST_DIR)/%.json
	cp $< $@

csetella-test: tools $(TEST_JS_FILES)

install-test: install csetella-test $(TEST_OUTPUT)/package.json $(TEST_OUTPUT)/test-config.json
	cd $(TEST_OUTPUT);\
	npm install;

test: install-test
	cp $(SOURCE_OUTPUT)/config.json $(TEST_OUTPUT);\
	$(MOCHA) --reporter spec $(TEST_OUTPUT)/*.js

.PHONY: test

# Web Server
web:
	-mkdir -p $(WEB_PUBLIC);\
	cp -R $(SOURCE_DIR)/web/* $(WEB_PUBLIC)

# Misc Rules

all: clean test

tools:
	-mkdir $(TOOLS);\
	cd $(TOOLS);\
	npm install mocha coffee-script forever

submit:
	cd ..; tar -jcvf ex3/$(SUBMIT_FILE) $(SUBMIT_EXCLUDE) $(SUBMIT_INCLUDE)
