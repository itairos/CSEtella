###
csetella.coffee

Unit Test Module for the CSEtella protocol.

Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###

###
Dependencies
###
csetella = require '../src/csetella'
{ Address, Message, MessageType, Parser, PingMessage, PongMessage, QueryMessage, ReplyMessage } = csetella
_ = require 'underscore'
async = require 'async'
should = require 'should'
winston = require 'winston'


# Set up a test logger
level = process.env['level']
level ?= 'warn'
logger = new winston.Logger { transports: [ new winston.transports.Console({ 'colorize': true, 'level': level }) ] }

###
Helper Functions
###
randomPayload = (length) ->
  s = ''
  s += Math.random().toString(36).substr(2) while s.length < length
  s.substr 0, length

randomMessageType = () ->
  types = _.keys(MessageType)
  MessageType[types[_.random(3)]]

randomMessage = () ->
  new Message { type : randomMessageType(), ttl : _.random(16), payload : if _.random(1) then randomPayload(_.random(1, 64)) else null }

chunkBuffer = (buffer, numberOfChunks = 2) ->
  chunks = []
  chunkSize = Math.ceil(buffer.length / numberOfChunks)
  for i in [0...buffer.length] by chunkSize
    chunk = buffer.slice(i, i + chunkSize)
    if chunk.length > 0
      chunks.push chunk
  # Sanity check: length of all chunks should be the length of the original buffer
  _.reduce(chunks, (memo, chunk) ->
    memo + chunk.length
  , 0).should.equal(buffer.length)
  return chunks
randomBuffer = (size) ->
  buffer = new Buffer size
  buffer[i] = _.random 0,255 for i in [0..size]
  return buffer

validateMessage = (message) ->
  message.should.have.property 'type'
  message.should.have.property('id').with.lengthOf(16)
  message.should.have.property('ttl').within(0, 255)
  message.should.have.property('hops').within(0, 255)
  message.should.have.property 'payload'


describe 'csetella', ->
  describe 'message', ->
    it 'should be able to serialize', ->
      options =
        type: MessageType.ping
        id: new Buffer 'abcdefghijklmnop'
        ttl: 5
        payload: new Buffer 'payload'
      m = new Message options
      should.exist m
      validateMessage m
      m.should.have.property property for property in [ 'id', 'type', 'ttl', 'hops', 'payload' ]
      m[k].should.equal v for k,v in options
      b = m.toBuffer()
      should.exist b
      b.length.should.equal(23 + options.payload.length)
      Message.AreBuffersEqual(options.id, b.slice(0,16)).should.be.true
      b.readUInt8(16).should.equal(MessageType.ping)
      b.readUInt8(17).should.equal(options.ttl)
      b.readUInt8(18).should.equal(0)
      b.readUInt32BE(19).should.equal(options.payload.length)
      Message.AreBuffersEqual(b.slice(23), options.payload)

    it 'should be able to deserialize', ->
      m1 = new Message { type : MessageType.query }
      should.exist m1
      validateMessage m1
      b1 = m1.toBuffer()
      m2 = Message.fromBuffer b1
      validateMessage m2
      b2 = m2.toBuffer()
      # Compare messages
      m2.isEqual(m1).should.equal true

    it 'should be able to deserialize with a random message id', ->
      m1 = new Message { type : MessageType.query, "id": randomBuffer(16) }
      should.exist m1
      validateMessage m1
      b1 = m1.toBuffer()
      m2 = Message.fromBuffer b1
      validateMessage m2
      b2 = m2.toBuffer()
      # Compare messages
      m2.isEqual(m1).should.equal true

    it 'should be able to hop', ->
      m = new Message { type : MessageType.ping }
      ttl0 = m.ttl
      while m.ttl > 0
        (m.ttl + m.hops).should.equal(ttl0)
        m.hop()

    it 'should be able to convert ip addresses from string/number to number/string', ->
      addresses =
        1634802238 : '97.113.26.62'
        3480018074 : '207.108.220.154'
        1249713255 : '74.125.28.103'
        2161115531 : '128.208.1.139'
        167772420 : '10.0.1.4'
        2851995904 : '169.254.1.0'
        2852060927 : '169.254.254.255'
        0 : '0.0.0.0'
        4294967295 : '255.255.255.255'
      # Test conversion from numbers to strings
      Message.convertNumberToIp(parseInt(number)).should.equal(ip) for number, ip of addresses
      # Test conversion from strings to numbers
      Message.convertIpToNumber(ip).should.equal(parseInt(number)) for number, ip of addresses

      parts = (x for x in [0..255] by 10)
      for part1 in parts
        for part2 in parts
          for part3 in parts
            for part4 in parts
              ip = "#{part1}.#{part2}.#{part3}.#{part4}"
              number = Message.convertIpToNumber(ip)
              Message.convertNumberToIp(number).should.equal(ip)

    it 'should be able to generate ping messages', ->
      m = new PingMessage
      should.exist m
      validateMessage m
      m.should.have.property 'type', MessageType.ping
      m.should.have.property 'payload', null

    it 'should be able to generate pong messages', ->
      ping = new PingMessage
      should.exist ping
      validateMessage ping
      address = new Address '10.0.1.19', 1234
      pong = new PongMessage ping, address
      should.exist pong
      validateMessage pong
      pong.should.have.property 'type', MessageType.pong
      pong.should.have.property 'id', ping.id
      pong.should.have.property 'ttl', (ping.ttl + ping.hops)
      payloadAddress = pong.payloadAsAddress()
      payloadAddress.should.have.property 'port', address.port
      payloadAddress.should.have.property 'host', address.host

    it 'should be able to generate query messages', ->
      m = new QueryMessage
      should.exist m
      validateMessage m
      m.should.have.property 'type', MessageType.query
      m.should.have.property 'payload', null

    it 'should be able to generate reply messages', ->
      query = new QueryMessage
      should.exist query
      validateMessage query

      address = new Address '10.0.1.19', 1234
      text = "  Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod tempor
        incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud
        exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor
        in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur
        sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."
      reply = new ReplyMessage query, address, text
      should.exist reply
      validateMessage reply

      reply.should.have.property 'type', MessageType.reply
      reply.should.have.property 'id', query.id
      payloadAddress = reply.payloadAsAddress()
      payloadAddress.port.should.equal address.port
      payloadAddress.host.should.equal address.host
      payloadText = reply.payloadAsString()
      payloadText.should.equal text


  describe 'parser', ->

    parser = null
    messages = []
    beforeEach ->
      parser = new Parser
      should.exist parser
      messageWithoutPayload = new Message { type : MessageType.query }
      should.exist messageWithoutPayload
      messages.push messageWithoutPayload
      messageWithPayload = new Message { type : MessageType.reply, payload : 'payload' }
      should.exist messageWithPayload
      messages.push messageWithPayload
    
    it 'should not be able to parse a partial message', ->
      for message in messages
        do (message) ->
          b = message.toBuffer()
          for i in [0...(b.length-1)]
            parsedMessages = parser.parse b.slice(0, i)
            parsedMessages.should.be.empty
            parser.reset()

    it 'should be able to parse a single message if it is received in one chunk', ->
      for message in messages
        do (message) ->
          parsedMessages = parser.parse message.toBuffer()
          should.exist parsedMessages
          parsedMessages.should.have.length 1
          should.exist parsedMessages[0]

    it 'should be able to parse a message if it is received in two chunks', ->
      for message in messages
        do (message) ->
          b = message.toBuffer()
          for i in [0..(b.length-2)]
            prefix = b.slice 0, i
            postfix = b.slice i
            parsedMessages = parser.parse prefix
            parsedMessages.should.be.empty
            parsedMessages = parser.parse postfix
            should.exist parsedMessages
            parsedMessages.should.not.be.empty
            _.first(parsedMessages).isEqual(message).should.equal true
            parser.reset()

    it 'should be able to parse many messages, one after the other, if each one is received in one chunk', ->
      for i in [0...200]
        message = randomMessage()
        b = message.toBuffer()
        parsedMessages = parser.parse b
        should.exist parsedMessages
        parsedMessages.should.not.be.empty
        parsedMessage = _.first parsedMessages
        if not parsedMessage.isEqual(message)
          console.log message
          console.log parsedMessage
          should.fail 'parsed message is different than the original message'

    it 'should be able to parse many messages, one after the other, even if messages are received in chunks', ->
      for i in [0...200]
        message = randomMessage()
        b = message.toBuffer()
        chunks = chunkBuffer b, _.random(2, 20)
        lastChunk = chunks[chunks.length - 1]
        allChunksButTheLastOne = chunks.slice(0, chunks.length - 1)
        parsedMessages = parser.parse chunk for chunk in allChunksButTheLastOne
        parsedMessages.should.be.empty
        parsedMessages = parser.parse lastChunk
        parsedMessages.should.not.be.empty
        parsedMessage = _.first parsedMessages
        if not parsedMessage.isEqual(message)
          console.log message
          console.log parsedMessage
          should.fail 'parsed message is different than the original message'

    it 'should not be able to parse a payload larger than 100Kb', ->
      message = randomMessage()
      message.payload = new Buffer(randomPayload(100 * 1024 + 2))
      b = message.toBuffer()
      err = parser.parse b
      should.exist err
      err.should.be.an.instanceof Error

  describe 'server', ->

    server = null
    beforeEach (done) ->
      server = csetella.createServer logger, (message, peer) ->
        if not server.messages? then server.messages = []
        server.messages.push message
      should.exist server
      server.listen done

    afterEach (done) ->
      server.close done

    it 'should be able to initialize', ->
      server.should.have.property 'peers'
      server.peers.should.be.an.instanceof Array
      server.peers.should.be.empty

    it 'should be able to accept multiple connections', (done) ->
      async.times 50, (n, next) ->
        peer = csetella.createPeer server.address(), () ->
          should.exist peer
          next null, peer
      , (err, peers) ->
        server.peers.should.have.length peers.length
        # All peers connected successfully, now destroy them
        async.each peers, (peer, callback) ->
          peer.destroy()
          callback null
        , (err) ->
          done err

    it 'should be able to accept a message from a peer', (done) ->
      peer = csetella.createPeer server.address(), () ->
        should.exist peer
        peer.ping () ->
          # Wait until the server receives the ping
          setTimeout () ->
            server.messages.should.have.length 1
            peer.end()
            done()
          , 100

    it 'should be able to accept multiple messages from a peer', (done) ->
      peer = csetella.createPeer server.address(), () ->
        should.exist peer
        async.timesSeries 1000, (n, next) ->
          message = peer.ping () ->
            next null, message
        , (err, messages) ->
          should.exist messages
          messages.should.have.property 'length'
          setTimeout () ->
            server.messages.length.should.equal messages.length
            peer.destroy()
            sentMessageIds = _.map _.pluck(messages, 'id'), (id) ->
              id.toString('hex')
            receivedMessageIds = _.map _.pluck(server.messages, 'id'), (id) ->
              id.toString('hex')
            allMessagesReceived = _.every sentMessageIds, (messageId) ->
              _.contains receivedMessageIds, messageId
            allMessagesReceived.should.be.true
            done err
          , 1000

    it 'should be able to time out when a peer is dead', (done) ->
      @timeout 5000
      options = { port: 25003, host: '10.0.1.111' }
      peer = server.connectToPeer options, 2000
      peer.on 'error', (err) ->
        console.log err
        server.peers.should.not.include peer
        peer.destroy()
        done()
      peer.on 'timeout', () ->
        server.peers.should.not.include peer
        peer.destroy()
        done()

    it 'should be able to connect to the gribble server and play ping pong', (done) ->
      @timeout 5000
      options = { port: 5002, host: '128.208.2.88' }
      pingMessage = null
      gribble = server.connectToPeer options

      server.on 'timeout', () ->
        done new Error('Connection failed.')

      server.once 'peer', (joined, peer) ->
        joined.should.be.true
        should.exist peer
        peer.should.equal gribble

        pingMessage = peer.ping()
        validateMessage pingMessage

      server.once 'message', (message, peer) ->
        should.exist message
        should.exist peer
        validateMessage message

        message.should.have.property 'type', MessageType.pong
        message.should.have.property 'id'
        Message.AreBuffersEqual(message.id, pingMessage.id).should.be.true
        message.should.have.property 'payload'

        address = message.payloadAsAddress()
        address.should.have.property 'port', options.port
        address.should.have.property 'host', options.host
        server.end()
        done()