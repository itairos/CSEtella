###
network-monitor.coffee

Unit Test Module for the NetworkMonitor class.

Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
net = require 'net'
should = require 'should'
moment = require 'moment'
winston = require 'winston'
{ NetworkMonitor } = require '../src/network-monitor'

PORT = 58299

level = process.env['level']
level ?= 'warn'
logger = new winston.Logger { transports: [ new winston.transports.Console({ 'colorize': true, 'level': level }) ] }

verifyAddress = (address, cb) ->
  # Verify the address provided to us is indeed valid by starting a server and trying to connect
  # to it using the provided address.
  # @note if running this test on a machine behind a NAT, make sure to open port 'PORT' on it. Also,
  # this test requires internet connectivity
  server = net.createServer (socket) ->
    socket.end()
    cb()
  server.listen PORT, () ->
    port = server.address().port
    net.connect server.address().port, address

describe 'network-monitor', ->

  describe '#start', ->

    it 'should not be able to start if queyring web services takes to long', (done) ->
      monitor = new NetworkMonitor(logger, { timeout: '50' })
      should.exist monitor
      monitor.start (err) ->
        should.exist err
        monitor.stop()
        done()

    it 'should be able to update the address cache', (done) ->
      @timeout 5000
      # This monitor will query the web services every second
      monitor = new NetworkMonitor(logger, { serviceQueryInterval: '1000' })
      should.exist monitor
      monitor.start (err) ->
        should.not.exist err
        setTimeout () ->
          should.exist monitor.lastUpdate
          moment().diff(monitor.lastUpdate).should.be.below(2000)
          monitor.stop()
          done()
        , 3000

  describe 'query', ->
    monitor = null
    beforeEach (done) ->
      monitor = new NetworkMonitor(logger)
      should.exist monitor
      monitor.start(done)

    afterEach ->
      monitor.stop()

    # @note make sure this machine is connected to a network when running this test
    it 'should be able to query the local IP addresses of this machine', ->
      NetworkMonitor.getLocalAddresses().should.not.be.empty

    # This test fails if behind NAT and port 'PORT' wasn't opened.
    it 'should be able to obtain the external ip of this machine', (done)->

      @timeout 10000
      monitor.getExternalAddress (err, address) ->
        should.not.exist err
        verifyAddress address, done
