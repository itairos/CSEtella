###
network-monitor.coffee
Implementation of class NetworkMonitor
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
os = require 'os'
fs = require 'fs'
moment = require 'moment'
request = require 'request'
_ = require 'underscore'


###
class NetworkMonitor
Helper class for querying the local and external IPv4 addresses of this machine and monitor changes
in the IP addresses assigned to this machine
###
class NetworkMonitor

  # Constants

  # Services used by this class to query the machine's external IP address
  @SERVICES = [
      "http://icanhazip.com/"
      "http://ifconfig.me/ip"
  ]
  # How long will the address cache be valid (default: 10 minutes)
  @DEFAULT_MAX_AGE_IN_MS = 10 * 60 * 1000
  # How often will this class contact the web services above to query the machine's external IP address
  @DEFAULT_QUERY_SERVICE_INTERVAL_IN_MS = 3 * 60 * 1000
  # How long will this class wait for a request to a web service to complete (defaul: 5 seconds) 
  @DEFAULT_SERVICE_REQUEST_TIMEOUT_IN_MS = 5 * 1000

  constructor: (@logger, options = {}) ->
    @externalAddress = null
    @lastUpdate = null
    @maxAgeInMsecs = options.maxAgeInMsecs
    @maxAgeInMsecs ?= NetworkMonitor.DEFAULT_MAX_AGE_IN_MS
    @timeout = options.timeout
    @timeout ?= NetworkMonitor.DEFAULT_SERVICE_REQUEST_TIMEOUT_IN_MS
    @monitor = null
    @serviceQueryInterval = options.serviceQueryInterval
    @serviceQueryInterval ?= NetworkMonitor.DEFAULT_QUERY_SERVICE_INTERVAL_IN_MS
    @logger.debug "Network monitor initialized (max age: #{@maxAgeInMsecs} msecs, timeout: #{@timeout} msecs, query interval: #{@serviceQueryInterval} msecs)"

  # Queries the external IP v4 address of the local machine.
  # @param {Function} callback which is called upon success or failure. The first argument is the error
  # and the second param is a string containing the external IP v4 of the local machine.
  _getExternalAddress: (force, cb) ->

    # If the external address is cached and is not stale yet, return it, instead of
    # asking the internets.
    @logger.debug "_getExternalAddress: force = #{force}, cached address: #{@externalAddress},
 last update: #{if @lastUpdate? then @lastUpdate.fromNow() else null}, max age: #{@maxAgeInMsecs} msecs."
    now = moment()
    if (not force) and @externalAddress? and @lastUpdate? and (now.diff(@lastUpdate) < @maxAgeInMsecs)
      return cb(null, @externalAddress)

    @logger.debug "_getExternalAddress: cache miss (or force is on), trying to query web services."
    # Cache miss (or we were forced)
    errorsCounter = 0
    # Invoke requests to all services in parallel and return the first (valid) ip address that
    # shows up. If all services failed, report the error to the caller via the provided callback.
    requests = _.map NetworkMonitor.SERVICES, (service) =>
      request { url: service, timeout: @timeout }, (err, res, body) =>
        # Strip all the whitespaces
        body = body.replace(/\s/, '') if body?

        # If there is no error, HTTP status code is 200, there is a body with an IP v4 pattern and
        # the callback hasn't been called yet, the IP address was successfully obtain.
        if (not err?) and res? and (res.statusCode is 200) and body? and
        body.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/)

          # Update the cache
          @lastUpdate = moment()
          @externalAddress = body

          # Call the callback and nullify it so it is not called again.
          if cb?
            cb null, @externalAddress
            cb =  null
        else
          errorsCounter++
          if errorsCounter is NetworkMonitor.SERVICES.length
            # All services failed :(
            # If the externalAddress has ever been set, return it even if it's stale
            if @externalAddress?
              @logger.debug "_getExternalAddress: failed to query all web services, returning a stale ip address."
              cb null, @externalAddress if @externalAddress?
            else
              cb new Error("Failed to obtain external IP address from all services"), null

  # Same as _getExternalAddress, cache will be used if possible
  getExternalAddress: (cb) ->
    @_getExternalAddress false, cb

  # Start monitoring changes in the external IP address of this machine
  # This is done by querying the online services above every X minutes.
  start: (cb) ->
    @_getExternalAddress true, (err, address) =>
      if not err?
        @monitor = setInterval () =>
          @_getExternalAddress true, (err, address) =>
            if err?
              @logger.warn "Failed to query the machine's IP address (error: #{err.stack}"
            else
              @logger.debug "Machine's IP address:", address
        ,@serviceQueryInterval
      cb err

  # Stops monitor IP address changes
  stop: ->
    clearInterval @monitor if @monitor?

  # Static method to query the local IP addresses of this machine
  @getLocalAddresses: ->
    _.pluck _.filter(_.flatten(_.values(os.networkInterfaces()), true), (address) ->
      (address.family is 'IPv4') and (not address.internal)
    ), 'address'


###
Exports
###
exports.NetworkMonitor = NetworkMonitor
