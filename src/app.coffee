###
app.coffee
Implementation of class Application
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
fs = require 'fs'
assert = require 'assert'
util = require 'util'
winston = require 'winston'
_ = require 'underscore'
memwatch = require 'memwatch'


###
class Application
This is an abstract base class which encapsulates a node.js application. It provides logging and
configuration services.
###
class Application

  # Class Constants
  @DEFAULT_CONFIG_FILENAME = "config.json"

  constructor: ->
    # Set up a CTRL+C, uncaught exception and termination handlers
    process.on 'SIGINT', =>
      @interrupt()
    process.on 'SIGTERM', =>
      @sigterm()
    process.on 'uncaughtException', (err) =>
      @uncaughtException err
    process.on 'exit', =>
      @exit()

    # Set up command line argument parser
    @args = Application._createCommandLineParser()
    @args.parse process.argv
    # Read configuration 
    @config = Application._parseConfig(@args.config)
    # Set up logging
    @logger = Application._createLogger(@config.logger)

    @createMemoryWatcher @config.debug

  @_createCommandLineParser: ->
    args = require 'commander'
    args.option '-c, --config [path]', 'configuration file; not required',
    Application.DEFAULT_CONFIG_FILENAME

  @_parseConfig: (filename) ->
    filename = Application.DEFAULT_CONFIG_FILENAME if not filename?
    JSON.parse fs.readFileSync(filename)

  @_createLogger: (loggerConfig) ->
    transports = []
    transports.push(new winston.transports.Console(loggerConfig.console)) if not _.isUndefined loggerConfig.console
    transports.push(new winston.transports.File(loggerConfig.file)) if not _.isUndefined loggerConfig.file
    return new winston.Logger { "transports" : transports }

  createMemoryWatcher: (debugConfig) ->
    if debugConfig.watchMemory
      @heapDiff = new memwatch.HeapDiff
      memwatch.on 'leak', (info) =>
        @logger.warn "Memory Leak Detected.\n#{util.inspect(info, { depth : null })}"
      memwatch.on 'stats', (stats) =>
        @logger.info "V8 finished garbage collection and heap compaction.\n#{util.inspect(stats, { depth : null })}"
        diff = @heapDiff.end()
        @logger.info "Heap Diff:\n#{util.inspect(diff, { depth : null })}"
        @heapDiff = new memwatch.HeapDiff

  # Application Handlers
  run: ->
    throw new Error "Implement this method in a subclass"

  start: ->
    @run()

  interrupt: ->
    @logger.info "User interrupted."
    process.exit 0

  sigterm: ->
    @logger.info "Got SIGTERM."
    process.exit 0

  exit: ->
    @logger.info "Terminating application."

  uncaughtException: (err) ->
    message = "Unhandled exception caught:\n#{err.stack}"
    # If an unhandled exception is thrown before a logger has been created, just use the console.
    if @logger? then @logger.error message else console.error message
    process.exit -1


###
Exports
###
exports.Application = Application
