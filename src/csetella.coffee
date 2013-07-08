###
csetella.coffee
Implementation of the CSEtella protocol.
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
net = require 'net'
util = require 'util'
events = require 'events'
assert = require 'assert'
uuid = require 'uuid'
_ = require 'underscore'
moment = require 'moment'
async = require 'async'

###
Constants
###
DEFAULT_TTL = 7 # This is also the default in the gnutella protocol
MAX_ALLOWED_TTL = 100
MAX_VALID_TTL = 0xFF
DEFAULT_HOPS = 0
MAX_ALLOWED_HOPS = 100
DEFAULT_IDLE_PEER_TIMEOUT_MSECS = 10 * 60 * 1000 # 10 minutes
DEFAULT_CONNECT_PEER_TIMEOUT_MSECS = 30 * 1000 # 30 seconds
MAX_PAYLOAD_SIZE = 1000 # 1000 bytes
# CSEtella Message Definition
MESSAGE_ID_OFFSET = 0
MESSAGE_ID_SIZE = 16
MESSAGE_TYPE_OFFSET = MESSAGE_ID_OFFSET + MESSAGE_ID_SIZE
MESSAGE_TYPE_SIZE = 1
MESSAGE_TTL_OFFSET = MESSAGE_TYPE_OFFSET + MESSAGE_TYPE_SIZE
MESSAGE_TTL_SIZE = 1
MESSAGE_HOPS_OFFSET = MESSAGE_TTL_OFFSET + MESSAGE_TTL_SIZE
MESSAGE_HOPS_SIZE = 1
MESSAGE_PAYLOAD_LENGTH_OFFSET = MESSAGE_HOPS_OFFSET + MESSAGE_HOPS_SIZE
MESSAGE_PAYLOAD_LENGTH_SIZE = 4
MESSAGE_PAYLOAD_OFFSET = MESSAGE_PAYLOAD_LENGTH_OFFSET + MESSAGE_PAYLOAD_LENGTH_SIZE
MESSAGE_HEADER_SIZE = MESSAGE_ID_SIZE + MESSAGE_TYPE_SIZE + MESSAGE_TTL_SIZE + 
                      MESSAGE_HOPS_SIZE + MESSAGE_PAYLOAD_LENGTH_SIZE
assert (MESSAGE_PAYLOAD_OFFSET is MESSAGE_HEADER_SIZE)

ADDRESS_PAYLOAD_PORT_OFFSET = 0
ADDRESS_PAYLOAD_PORT_SIZE = 2
ADDRESS_PAYLOAD_IP_OFFSET = ADDRESS_PAYLOAD_PORT_OFFSET + ADDRESS_PAYLOAD_PORT_SIZE
ADDRESS_PAYLOAD_IP_SIZE = 4
ADDRESS_PAYLOAD_SIZE = ADDRESS_PAYLOAD_PORT_SIZE + ADDRESS_PAYLOAD_IP_SIZE
TEXT_PAYLOAD_OFFSET = ADDRESS_PAYLOAD_SIZE

# Message Type
MessageType =
  ping: 0
  pong: 1
  query: 2
  reply: 3
  toString: (type) ->
    switch type
      when MessageType.ping then return 'Ping'
      when MessageType.pong then return 'Pong'
      when MessageType.query then return 'Query'
      when MessageType.reply then return 'Reply'
      else return "Unknown Type: #{type}"


###
class Address
###
class Address
  constructor: (@host, @port) ->

  toString: ->
    "#{@host}:#{@port}"


###
class Message
Abstract base class for all messages in the CSEtella protocol
@param {Object} options the parameters used to build the message. This object must have
  the key 'type' which is the type of the message (pin, pong etc. see MessageType). The
  object can have the keys 'ttl' (Number), 'id' (String of length 16) and 'payload' (Buffer)
###
class Message
  constructor: (options = {}) ->
    @id = if options.id? then options.id else new Buffer(uuid.v4().replace(/-/g,'')[0..15])
    @type = options.type # options MUST
    @ttl = if options.ttl? then options.ttl else DEFAULT_TTL
    @hops = if options.hops? then options.hops else DEFAULT_HOPS
    assert (@ttl + @hops) <= MAX_VALID_TTL
    @payload = null
    if options.payload?
      if _.isString options.payload
        @payload = new Buffer(options.payload, 'ascii')
      else if Buffer.isBuffer(options.payload)
        @payload = options.payload
      assert @payload.length <= MAX_PAYLOAD_SIZE if @payload?

  # Returns a human readable string describing this message
  toString: ->
    "Message #{MessageType.toString(@type)} <<#{@id.toString('hex')}>>: TTL = #{@ttl}, HOPS = #{@hops}, Payload Size
 = #{if @payload? then @payload.length else 0}"

  # Serializes the message
  toBuffer: ->
    payloadLength = if @payload? then @payload.length else 0
    buffer = new Buffer(MESSAGE_HEADER_SIZE + payloadLength)
    @id.copy buffer, MESSAGE_ID_OFFSET, 0, MESSAGE_ID_SIZE
    buffer.writeUInt8 @type, MESSAGE_TYPE_OFFSET
    buffer.writeUInt8 @ttl, MESSAGE_TTL_OFFSET
    buffer.writeUInt8 @hops, MESSAGE_HOPS_OFFSET
    buffer.writeUInt32BE payloadLength, MESSAGE_PAYLOAD_LENGTH_OFFSET
    if @payload?
      @payload.copy buffer, MESSAGE_PAYLOAD_OFFSET
    return buffer

  # Updates ttl, and hops when routed
  hop: ->
    if @ttl > 0
      @ttl = @ttl - 1
      @hops = @hops + 1

  isDead: ->
    @ttl is 0

  # Static method to convert an ip from number to string
  @convertNumberToIp: (number) ->
    return null if not _.isNumber number
    ip = number % 256
    for i in [0...3]
      number = Math.floor(number / 256)
      ip = (number % 256) + '.' + ip
    return ip

  @convertIpToNumber: (ip) ->
    return null if not _.isString ip
    # Split the string to its ip parts
    parts = ip.split '.'
    # Make sure there are exactly 4 parts
    return null if parts.length isnt 4
    # Convert each part to a number in base 10
    parts = _.map parts, (part) ->
      parseInt part, 10
    # Encode the parts as a number
    return ((((((+parts[0]) * 256) + (+parts[1])) * 256) + (+parts[2])) * 256) + (+parts[3])

  # Converts the payload of this message to an address object (i.e. { port: 3000, host: '10.0.1.4' })
  # If the pyaload does not represent an address (i.e. message type is not 'pong'), null is returned
  payloadAsAddress: ->
    assert @type is MessageType.reply or @type is MessageType.pong
    return new Error "Message has no payload." if not @payload?
    return new Error "Message payload is too short to contain an address." if @payload.length < ADDRESS_PAYLOAD_SIZE
    port = @payload.readUInt16BE ADDRESS_PAYLOAD_PORT_OFFSET
    ipAsNumber = @payload.readUInt32BE ADDRESS_PAYLOAD_IP_OFFSET
    # Convert to an ip string
    ip = Message.convertNumberToIp ipAsNumber
    return new Address ip, port

  # Converts the payload of this message to a string. Returns null, if no payload is available 
  payloadAsString: ->
    assert @type is MessageType.reply
    return null if (_.isNull @payload) or (@payload.length < ADDRESS_PAYLOAD_SIZE)
    return @payload.slice(TEXT_PAYLOAD_OFFSET).toString('ascii')

  # Buffer comparator
  @AreBuffersEqual: (buffer1, buffer2) ->
    # If one of the buffers is null and the other isn't => inequality
    return false if (buffer1 is null and buffer2 isnt null) or (buffer1 isnt null and buffer2 is null)

    # If both buffers are null => equality
    return true if buffer1 is null and buffer2 is null

    # If buffers have different lengths => inequality
    return false if buffer1.length isnt buffer2.length

    # Compare byte by byte
    for i in [0...buffer1.length]
      return false if buffer1[i] isnt buffer2[i]
    return true

  # Payload Comparator
  isPayloadEqual: (other) ->
    Message.AreBuffersEqual @payload, other.payload

  # Comparator
  isEqual: (other) ->
    Message.AreBuffersEqual(@id, other.id) and @type is other.type and @ttl is other.ttl and
    @hops is other.hops and @isPayloadEqual other

  isIdEqual: (other) ->
    Message.AreBuffersEqual @id, other.id

  # Checks whether this message is valid. This is called by the parser code, as well as before sending
  # a message to any peer. The 'buffer' argument is optional and is used for diagnostic purposes.
  checkIfValid: (buffer = null) ->

    if @ttl > MAX_ALLOWED_TTL
      return new Error "TTL is too big: #{@ttl}"

    if @hops > MAX_ALLOWED_HOPS
      return new Error "Hops is too big: #{@hops}"

    if @payload? and @payload.length > MAX_PAYLOAD_SIZE
      return new Error "Payload is too big: #{@payload.length}"

    if @type is MessageType.ping or @type is MessageType.query
      if @payload? and @payload.length > 0
        return new Error "Ping and Query messages should NOT have a payload."

    if @type is MessageType.pong
      if not @payload?
        return new Error "Pong messages MUST contain a payload."
      if @payload.length isnt ADDRESS_PAYLOAD_SIZE
        return new Error "Pong messages MUST contain a payload of size 6"

    if @type is MessageType.reply
      text = @payloadAsString()
      return new Error "Reply messages must contain text in their payload" if not text?
      if /[\x00-\x1F]/.test(text) or /[\x80-\xFF]/.test(text)
        data = new Buffer(text)
        buffer = new Buffer('Buffer was not provided') if not buffer?
        return new Error "Reply message payload contains non-printable characters : Text: #{text}, HEX: #{data.toString('hex')}, Message: #{@toString()}, Original buffer: #{buffer.toString('hex')}"

    # Message is valid.
    return null

  # Deserializes a message, returns an Error object upon parsing error
  @fromBuffer: (buffer) ->
    # Sanity checks
    return new Error "No Data" if  not buffer?
    return new Error "Not Enough Data" if buffer.length < MESSAGE_HEADER_SIZE

    # Parse message id
    id = new Buffer MESSAGE_ID_SIZE
    buffer.copy id, 0, 0, MESSAGE_ID_SIZE

    # Parse message type
    type = buffer.readUInt8 MESSAGE_TYPE_OFFSET
    return new Error "Invalid Message Type" if type not in [ MessageType.ping, MessageType.pong, MessageType.query, MessageType.reply]

    # Parse ttl, hops
    ttl = buffer.readUInt8 MESSAGE_TTL_OFFSET
    hops = buffer.readUInt8 MESSAGE_HOPS_OFFSET
    # Basic sanity checking on ttl and hops
    return new Error "TTL is too big: TTL = #{ttl}" if ttl > MAX_ALLOWED_TTL
    return new Error "HOPS is too big: HOPS = #{hops}" if hops > MAX_ALLOWED_HOPS
    # If TTL + hops > 255, then ttl0 was bigger than 0xFF which isn't possible.
    return new Error "Message has invalid TTL/hop combination: TTL = #{ttl}, hops = #{hops}" if (ttl+hops) > MAX_VALID_TTL

    # Parse payload
    payloadLength = buffer.readUInt32BE MESSAGE_PAYLOAD_LENGTH_OFFSET
    return new Error "Invalid Payload Length" if (buffer.length - MESSAGE_HEADER_SIZE) isnt payloadLength
    payload = null
    if payloadLength > 0
      payload = new Buffer payloadLength
      buffer.copy payload, 0, MESSAGE_PAYLOAD_OFFSET

    message = new Message({ "id" : id, "type" : type, "ttl" : ttl, "hops" : hops, "payload" : payload })
    err = message.checkIfValid(buffer)
    return err if err?

    return message


class PingMessage extends Message
  constructor: (options = {}) ->
    options.type = MessageType.ping
    super options


class PongMessage extends Message
  constructor: (pingMessage, address, options = {}) ->
    # Sanity Checks
    return null if _.isNull pingMessage
    return null if (_.isNull address) or (_.isNull address.port) or (_.isNull address.host)

    # Set the message type to be 'pong'
    options.type = MessageType.pong

    # Set the message id to be the same as the ping message's id
    options.id = pingMessage.id

    # Set the TTL of the pong message to be the original TTL of the ping message. This will guarantee
    # that the TTL is big enough to allow routing the message back to the originating node.
    options.ttl = pingMessage.ttl + pingMessage.hops
    if options.ttl > MAX_ALLOWED_TTL
      options.ttl = MAX_ALLOWED_TTL

    # Generate payload
    # First convert the ip address to a number
    number = Message.convertIpToNumber address.host
    return null if _.isNull number
    # Write the port, ip to the payload buffer
    payload = new Buffer ADDRESS_PAYLOAD_SIZE
    payload.writeUInt16BE address.port, ADDRESS_PAYLOAD_PORT_OFFSET
    payload.writeUInt32BE number, ADDRESS_PAYLOAD_IP_OFFSET
    options.payload = payload

    # Call the Message constructor with all of the options we set
    super options


class QueryMessage extends Message
  constructor: (options = {}) ->
    options.type = MessageType.query
    super options


class ReplyMessage extends Message
  constructor: (queryMessage, address, text, options = {}) ->
    # Sanity checks
    return null if _.isNull queryMessage
    return null if (_.isNull text) or (not _.isString text)
    return null if (_.isNull address)
    # Set the message to be a 'reply' message
    options.type = MessageType.reply
    # Copy the id for this message from the query message.
    options.id = queryMessage.id

    # Set the TTL of the reply message to be the original TTL of the query message. This will guarantee
    # that the TTL is big enough to allow routing the message back to the originating node.
    options.ttl = queryMessage.ttl + queryMessage.hops
    if options.ttl > MAX_ALLOWED_TTL
      options.ttl = MAX_ALLOWED_TTL

    # Generate payload
    # First convert the ip address to a number
    number = Message.convertIpToNumber address.host
    return null if _.isNull number
    # Set the payload of this message to be the eaddress and text
    lengthOfTextInBytes = Buffer.byteLength(text, 'ascii')
    payload = new Buffer(ADDRESS_PAYLOAD_SIZE + lengthOfTextInBytes)
    payload.writeUInt16BE address.port, ADDRESS_PAYLOAD_PORT_OFFSET
    payload.writeUInt32BE number, ADDRESS_PAYLOAD_IP_OFFSET
    payload.write text, TEXT_PAYLOAD_OFFSET, lengthOfTextInBytes, 'ascii'
    options.payload = payload
    super options


###
class Parser
Encapsulates a CSEtella message parser. One parser instance is created per peer (socket).
###
class Parser
  constructor: ->
    @reset()

  # Call 'parse' anytime more data becomes available from a peer. Returns an array of parsed CSEtella
  # messages (the array can be empty is more data is needed) or an Error object if parsing failed.
  parse: (data) ->
    @data = if _.isNull(@data) then data else Buffer.concat [ @data, data ]
    messages = []
    while @data.length >= MESSAGE_HEADER_SIZE
      # Try to parse the payload length and see if the entire message already arrived
      payloadLength = @data.readUInt32BE MESSAGE_PAYLOAD_LENGTH_OFFSET
      return [ new Error "Payload is too big." ] if payloadLength > MAX_PAYLOAD_SIZE
      messageLength = (MESSAGE_HEADER_SIZE + payloadLength)
      if @data.length >= messageLength
        # The entire message has been received, parse it
        messageBuffer = @data.slice 0, messageLength
        message = Message.fromBuffer messageBuffer
        # Add the message/error to the messages array
        messages.push message
        # If there was a parsing error, stop parsing and return the messages parsed so far and the error
        return messages if message instanceof Error
        @data = @data.slice messageLength
      else
        # The payload was not received yet, return the parsed messages so far
        break
    return messages

  reset: ->
    @data = null


###
class Peer
Encapsulates a CSEtella peer.
###
class Peer extends events.EventEmitter
  constructor: (@socket) ->
    
    # Sanity check
    return null if _.isNull @socket

    # Create a parser for this peer
    @parser = new Parser
    @name = ""
    @lastMessageTimestamp = null

    # After the socket is closed, its port and address become undefined. For debugging purposes
    # cache the 'toString()' of this peer now.
    @description = @toString()
    
    # Configure the socket to use the parser when new data becomes available
    @socket.on 'data', (chunk) =>
      messages = @parser.parse chunk
      for message in messages
        do (message) =>
          if message instanceof Error
            # There was a parsing error, peer is sending malformed data
            @emit 'error', message
          else if not _.isNull message
            @lastMessageTimestamp = moment()
            @setNameFromMessage message
            @emit 'message', message

    # Forward the 'close' event from the socket
    @socket.on 'close', (hadError) =>
      @emit 'close', hadError

    # Forward the 'error' event from the socket
    @socket.on 'error', (err) =>
      @emit 'error', err

    # Forward the 'timeout' event from the socket
    @socket.on 'timeout', () =>
      @emit 'timeout'

    # Forward the 'connect' event from the socket
    @socket.on 'connect', () =>
      # If the socket was not connected when the constructor was called, set the description now.
      @description = @toString()
      @emit 'connect'

  setNameFromMessage: (message) ->
    if message.type is MessageType.reply
      address = message.payloadAsAddress()
      if not (address instanceof Error)
        if address.port is @socket.remotePort and address.host is @socket.remoteAddress
          @name = message.payloadAsString()

  end: () ->
    @socket.end()
    @destroy()

  destroy: () ->
    @socket.destroy()

  send: (message, cb) ->
    # Send only valid messages!
    err = message.checkIfValid()
    if not err?
      data = message.toBuffer()
      assert data isnt null
      @socket.write data, cb

  setTimeout : (msecs) ->
    @socket.setTimeout msecs

  # Send a ping message
  ping: (cb) ->
    message = new PingMessage
    @send message, cb
    return message

  # Send a query message
  query: (cb) ->
    message = new QueryMessage
    @send message, cb
    return message

  # Returns a human readable string describing this peer
  toString: () ->
    "#{@socket.remoteAddress}:#{@socket.remotePort}"

  toJSON: ->
    connectedFor = if @connectedOn then @connectedOn.fromNow(true) else null
    { "host": @socket.remoteAddress, "port": @socket.remotePort, "connectedFor": connectedFor, "name": @name }

  port: ->
    @socket.remotePort

  host: ->
    @socket.remoteAddress


createPeer = (options, connectionListener) ->
  new Peer net.createConnection(options, connectionListener)


###
class Server
Encapsulates a CSEtella server. Its main role is to parse the CSEtella protocol and manage the
connection lifecycle of clients.
@param {Function} callback which is called every time a new csetella message is received by the server.
###
class Server extends net.Server
  constructor: (@logger, messageListener) ->
    super @connectionListener
    @peers = []
    @addListener 'message', messageListener

  connectionListener: (socket) ->

    # Build a peer object from the new connection
    peer = new Peer socket

    # Add the socket to the list of peers
    @addPeer peer

  # Adds a peer to the server, note that only connected peers (for which the 'connect' event
  # was emitted) should be added to the server
  addPeer: (peer) ->

    # Sanity check
    assert not _.contains @peers, peer

    # Set an idle timeout of all peers
    peer.setTimeout DEFAULT_IDLE_PEER_TIMEOUT_MSECS
    # If a peer times out, disconnect from it
    peer.on 'timeout', () ->
      peer.destroy()

    # Forward messages from the peer to the messageListener
    peer.on 'message', (message) =>
      @emit 'message', message, peer

    # Remove the peer from the peer list when it is closed
    peer.on 'close', (hadError) =>
      @_removePeer peer

    # Disconnect from the peer, in case of an error
    peer.on 'error', (err) =>
      if err.message isnt "This socket is closed."
        @logger.error "Disconnecting #{peer.description} due to an error: #{err}"
      peer.end()
      @_removePeer peer

    # Mark when the peer connected
    peer.connectedOn = moment()
    # Finally, add the peer to the list of connected peers and notify listeners
    assert peer?
    @peers.push peer
    @emit 'peer', true, peer


  connectToPeer: (options, timeout = DEFAULT_CONNECT_PEER_TIMEOUT_MSECS, cb = null) ->
    peer = createPeer options
    # If the server failed to connect to the peer within the alloted timeout, destroy the peer
    # without adding it to the list of connected peers, it's probably dead or unreachable.
    peer.setTimeout timeout
    peer.on 'timeout', ->
      peer.destroy()
      cb new Error "Connection timed out.", null if cb?
      cb = null

    peer.on 'error', (err) ->
      peer.destroy()
      cb err, null if cb?
      cb = null

    # Once the peer connected, remove the short connection timeout and add it
    # to the list of connected peers
    peer.on 'connect', () =>
      peer.setTimeout 0 # Disable timeouts
      @addPeer peer
      cb null, peer if cb?

    return peer

  isConnectedToPeer: (peerAddress) ->
    _.find(@peers, (peer) =>
      peer.port() is peerAddress.port and peer.host() is peerAddress.host
    )?

  end: () ->
    peer.end() for peer in @peers

  _removePeer: (peer) ->

    # Find the peer in the list of peers and remove it.
    index = @peers.indexOf peer
    if index isnt -1
      @peers.splice index, 1
      @emit 'peer', false, peer

  # Returns a json representing the current status of the server
  toJSON: ->
    "address": @address()
    "peers": _.map @peers, (peer) ->
      peer.toJSON()


###
class Crawler
###
class Crawler
  constructor: (@logger, @config) ->

    @root = @config.root
    @timeout = @config.timeoutInMsec
    @refreshInterval = @config.refreshIntervalInMsecs
    @logger.debug "Crawler: root = #{util.inspect(@root, { depth : null })}, timeout = #{@timeout}, refresh = #{@refreshInterval}"

    @topology =
      "nodes": []
      "edges": []
      "lastUpdated": "Never. Please wait for crawler to finish running."

  _queryPeers: (address, cb) ->

    messages = []
    query = new QueryMessage { "ttl": 2 }

    @logger.debug "Crawl: querying peers of #{address.host}:#{address.port}."
    peer = createPeer address
    peer.setTimeout @timeout

    peer.on 'timeout', ->
      peer.destroy()
      cb new Error "Connection timed out.", null if cb?
      cb = null

    peer.on 'error', (err) ->
      peer.destroy()
      cb err, null if cb?
      cb = null

    peer.on 'message', (message) =>
      @logger.debug "Crawl: #{message.toString()}"
      if (message.type is MessageType.reply) and query.isIdEqual(message)
        @logger.debug "Crawl: Found a peer: #{util.inspect(message.payloadAsAddress(), { depth : null })}"
        messages.push message

    peer.on 'connect', () =>
      @logger.debug "Crawl: connected to peer #{peer.toString()}. Sending Query: #{query.toString()}"
      peer.send query
      setTimeout () =>
        peers = _.map messages, (message) =>
          { "address": message.payloadAsAddress(), "text": message.payloadAsString() }
        @logger.debug "Crawl: Found the following peers for node: #{peer.toString()}: #{util.inspect(peers, { depth : null })}"
        if cb?
          cb null, peers
          cb = null
          peer.end()
      , @timeout

  start: ->
    @crawl () =>
      setTimeout () =>
        @start()
      , @refreshInterval

  crawl: (cb) ->

    rootDescriptor = "#{@root.host}:#{@root.port}"
    @logger.debug "Crawl: Starting at: #{rootDescriptor}"
    
    #
    # Nodes and edges are both represented as strings.
    # Node Format: {IP}:{Port}
    # Edge Format: {Node1}->{Node2}
    # Note: edges are not directed!
    #
    topology =
      "nodes": [ rootDescriptor ],
      "edges": []

    queue = [ { "address": @root, "text": "" } ]
    color = { rootDescriptor: "gray" }
    async.whilst () =>
      return queue.length > 0
    , (callback) =>
      current = queue.shift()
      currentDescriptor = "#{current.address.host}:#{current.address.port}"
      @_queryPeers current.address, (err, peers) =>
        if not err?
          for peer in peers
            peerDescriptor = "#{peer.address.host}:#{peer.address.port}"
            # Add an edge to the topology
            # Filter the 'reply' message that the 'current' node returned. Only the 'reply' messages
            # from its peers will be counted as edges
            if currentDescriptor isnt peerDescriptor

              # Dedup edges, the generated graph is not directed so A->B equal B->A
              edge = "#{currentDescriptor}->#{peerDescriptor}"
              inverseEdge = "#{peerDescriptor}->#{currentDescriptor}"
              if (not _.contains(topology.edges, edge)) and (not _.contains(topology.edges, inverseEdge))
                @logger.debug "Crawl: Edge: #{edge}"
                topology.edges.push edge
            
            if not color[peerDescriptor]? # Has white color
              color[peerDescriptor] = "gray"
              # Discovered a new vertex in the graph --> add to the list of nodes
              @logger.debug "Crawl: Vertex: #{peerDescriptor}"
              if not _.contains topology.nodes, peerDescriptor
                topology.nodes.push peerDescriptor
              # Add to the BFS queue
              queue.push peer
        else
          @logger.debug "Crawl: failed querying the peers of #{currentDescriptor} (#{err})"
        color[currentDescriptor] = "black"
        callback()
    , (err) =>
      @logger.debug "Crawl: End."
      topology.lastUpdated = moment().format "dddd, MMMM Do YYYY, h:mm:ss a"
      @topology = topology
      cb err, @topology if cb?


###
Exports
###
exports.Address = Address
exports.Message = Message
exports.PingMessage = PingMessage
exports.PongMessage = PongMessage
exports.QueryMessage = QueryMessage
exports.ReplyMessage = ReplyMessage
exports.MessageType = MessageType
exports.Parser = Parser
exports.Peer = Peer
exports.Crawler = Crawler
exports.createServer = (logger, messageListener) ->
  new Server logger, messageListener
exports.createPeer = createPeer