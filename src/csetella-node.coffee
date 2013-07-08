###
csetella-node.coffee
Implementation of a CSEtella node (i.e. a CSEtella client, server and router).
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
path = require 'path'              # Path manipulation
dns = require 'dns'                # Name Resolution
events = require 'events'          # Event emission
_ = require 'underscore'           # Utilities
async = require 'async'            # Asynchronous utils
moment = require 'moment'          # Time utilities
Cache = require 'lru-cache'        # LRU cache for sent/received messages
assert = require 'assert'          # Sanity checking
levelup = require 'levelup'        # Durable storage
express = require 'express'        # Web Server
{ Application } = require './app'  # Application wrapper
{ NetworkMonitor } = require './network-monitor' # For querying external IP address of this machine
csetella = require './csetella'    # The CSEtella protocol implementation
{ Address, MessageType, PingMessage, PongMessage, QueryMessage, ReplyMessage, Crawler } = csetella


# Helper method added to the String class
if typeof String.prototype.startsWith isnt 'function'
  String.prototype.startsWith = (str) ->
    @slice(0, str.length) is str

###
class NodeStore
This node uses Google's LevelDB to store the discovered peers and the text they share. The
former will allow us to bootstrap the node in case the gribble server is down. The latter
is needed for submitting this assignment :)
###
class NodeStore

  # Constants
  PEER_PREFIX = "peer"
  TEXT_PREFIX = "text"

  constructor: (@logger, location, cb) ->
    @db = levelup location, { 'valueEncoding' : 'json' }, cb

  close: (cb) ->
    @db.close cb

  # Stores the peer in the store.
  addPeer: (peer, cb) ->
    @db.put "#{PEER_PREFIX}:#{peer.toString()}", new Date().getTime(), (err) =>
      @logger.warn "Storing a peer failed. (error: #{err.stack})" if err?
      cb err if cb?

  addPeerAddress: (address, cb) ->
    @db.put "#{PEER_PREFIX}:#{address.host}:#{address.port}", new Date().getTime(), (err) =>
      @logger.warn "Storing a peer failed. (error: #{err.stack})" if err?
      cb err if cb?

  addSharedText: (text, cb) ->
    @db.put "#{TEXT_PREFIX}:#{text}", new Date().getTime(), (err) =>
      @logger.warn "Storing shared text failed. (error: #{err.stack})" if err?
      cb err if cb?

  _getAllItemsWithPrefix: (prefix, cb) ->
    items = []
    prefixRegExp = new RegExp "^#{prefix}:"
    @db.createReadStream()
    .on 'data', (data) =>
      if data.key.startsWith prefix
        key = data.key.replace prefixRegExp, ''
        items.push { "key":key, "value": data.value }
    .on 'err', (err) =>
      if cb?
        cb err, null
        cb = null
    .on 'end', () =>
      if cb?
        cb null, items
        cb = null

  # Returns the peers in this store sorted by the time they were stored. Peers added last are first in the list
  getPeers: (cb) ->
    
    peers = []
    @_getAllItemsWithPrefix PEER_PREFIX, (err, pairs) =>

      if not err?
        # Convert the key, value pairs to 'address' objects (with host,port)
        peers = _.map pairs, (pair) ->
          [ host, port ] = pair.key.split ':'
          { "host": host, "port": parseInt(port), "timestamp": pair.value }

        # Filter out invalid peers if such exist
        peers = _.filter peers, (peer) ->
          not _.isUndefined(peer.host) and not _.isUndefined(peer.port) and not _.isUndefined(peer.timestamp)

        # Sort the peers by their timestamp
        peers = _.sortBy peers, (peer) ->
          # _.sortBy sorts in ascending order, add a - before the timestamp to make sure the last
          # added peer is first (Therefore it is more likely to be up and running).
          -peer.timestamp

      cb err, peers

  # Returns all the texts shared by other peers
  getAllSharedTexts: (cb) ->
    peers = []
    @_getAllItemsWithPrefix TEXT_PREFIX, (err, pairs) =>
      if not err?
        # Remove the values from all pairs, as the shared test is the key
        keys = _.pluck pairs, 'key'
        # Filter out the leys with non printable characters.
        filteredKeys = _.filter keys, (key) =>
          not /[\x00-\x1F]/.test(key)
      cb err, filteredKeys

  @_prettifyPeers: (peers, cb) ->
    async.each peers, (peer, callback) ->
      dns.reverse peer.host, (err, domains) ->
        if not err? and domains.length > 0
          peer.hostname = domains[0]
        peer.lastSeen = moment(peer.timestamp).fromNow()
        callback()
    , (err) ->
      cb err, peers

  status: (cb) ->
    async.parallel [
      (callback) =>
        @getAllSharedTexts callback
      ,
      (callback) =>
        @getPeers (err, peerAddresses) =>
          if not err?
            NodeStore._prettifyPeers peerAddresses, (err, prettyPeers) =>
              callback err, peerAddresses
          else
            callback err, peerAddresses
    ],
    (err, results) =>
      texts = if results.length > 0 then results[0] else null
      discoveredPeers = if results.length > 1 then results[1] else null
      cb err, { "discoveredPeers": discoveredPeers, "texts": texts }


###
class NodeStats
Maintains the statistics of the node
###
class NodeStats
  constructor: () ->
    @startedOn = null
    # Counters
    @received =
      pings: 0
      pongs: 0
      queries: 0
      replies: 0
    @sent =
      pings: 0
      pongs: 0
      queries: 0
      replies: 0

  logStart: () ->
    @startedOn = moment()

  @_logMessage: (message, obj)->
    switch message.type
      when MessageType.ping then obj.pings++
      when MessageType.pong then obj.pongs++
      when MessageType.query then obj.queries++
      when MessageType.reply then obj.replies++

  logReceivedMessage: (message)->
    NodeStats._logMessage message, @received

  logSentMessage: (message)->
    NodeStats._logMessage message, @sent

# The routing operation type used internall in class Node below
RouteType =
  forward: 0 # For pings/queries
  routeBack: 1 # for pongs/replies


###
class Node
Encapsulates a CSEtella node (client, server and router)
###
class Node extends events.EventEmitter
  constructor: (@options, @logger) ->

    ###
    Set up the message caching
    The message cache is a key-value LRU cache.
    Keys in the cache are string with the following format: {message id}:{message type}
    This format creates an index on the message id,type which allows a caller to query whether
    a message with a given id and type has been received by this node.
    The value of each entry in the cache, is the peer the sent it. This is needed to route back
    a message to the originating node on the same network path.
    ###
    @messageCache = new Cache @options.cache

    @monitor = new NetworkMonitor @logger, @options.monitor

    # Will be an instance of NodeStore after 'start' is called. See documentation of
    # class NodeStore for more details about the store.
    @store = null

    # Node stats
    @stats = new NodeStats()

    # These will be tickets returned by setInterval and represent the
    # periodic jobs that send ping/query to peers.
    # This array will contain all the periodic task this node has (pinging/querying/connecting peers)
    @periodicTasks = []

    # Set up the CSEtella server
    @server = csetella.createServer @logger, (message, peer) =>
      if message? and peer?
        @stats.logReceivedMessage message
        @logger.debug "Received: #{message.toString()} from #{peer.toString()}"
        @emit 'msgrecv', message, peer # For testing
        # Redirect the messages to their handlers
        switch message.type
          when MessageType.ping then @onPing message, peer
          when MessageType.pong then @onPong message, peer
          when MessageType.query then @onQuery message, peer
          when MessageType.reply then @onReply message, peer

    # Listen to peer join/leave events
    @server.on 'peer', (joined, peer) =>
      @onPeer joined, peer

    @server.maxConnections = @options.csetella.maxConnections

  # Starts the node
  start: (cb) ->
    @logger.info "Starting CSEtella node."
    @stats.logStart()
    async.parallel [
      (callback) =>
        # Start listening
        @server.listen @options.csetella.preferredPort, callback
      ,
      (callback) =>
        # Start monitoring the IP address of this machine
        @monitor.start callback
      ,
      (callback) =>
        # Start the database
        @store = new NodeStore @logger, @options.storage.location, callback
    ],
    (err, results) =>
      # All tasks completed, call the caller's provided callback
      if err?
        @logger.error "Failed to start node #{err.stack}"
      else
        @logger.info "CSEtella node started (port = #{@server.address().port})"
        # Starts the periodic tasks, only if the node started successfully.
        @periodicTasks.push setInterval () =>
          @pingAllPeers()
        , @options.csetella.pingIntervalInMsecs
        @periodicTasks.push setInterval () =>
          @queryAllPeers()
        , @options.csetella.queryIntervalInMsecs
        @periodicTasks.push setInterval () =>
          @tryConnectingPeers()
        , @options.csetella.connectionMaintenanceIntervalInMsecs
        @periodicTasks.push setInterval () =>
          @tryDisconnectingPeers()
        , @options.csetella.connectionMaintenanceIntervalInMsecs
        # Kick off connections to known peers
        for peerAddress in @options.csetella.knownPeers
          @server.connectToPeer peerAddress, 5000
        @tryConnectingPeers()
      cb err

  pingAllPeers: ->
    ping = new PingMessage
    @logger.info "Pinging peers (#{@server.peers.length} peers): #{ping.toString()}" if @server.peers.length > 0
    @send peer, ping for peer in @server.peers

  queryAllPeers: ->
    query = new QueryMessage
    @logger.info "Querying peers (#{@server.peers.length} peers): #{query.toString()}" if @server.peers.length > 0
    @send peer, query for peer in @server.peers

  isLonely: ->
    @server.peers.length < @options.csetella.maxPeers

  tryConnectingPeers: ->
    if @isLonely()
      @logger.info "Node has #{@server.peers.length} peers. Will try to connect to more peers 
(until node has #{@options.csetella.maxPeers})"

      # Try to connect to the discovered peers
      @store.getPeers (err, peerAddresses) =>
        if not err?
          async.whilst () =>

            isStillLonely = @isLonely()
            @logger.debug "Node has #{@server.peers.length} peers. Needs more? #{isStillLonely}."
            return (isStillLonely and (peerAddresses.length > 0))

          , (callback) =>
            peerAddress = peerAddresses.shift()
            if not @server.isConnectedToPeer peerAddress
              @logger.debug "Trying to connect to peer: #{peerAddress.host}:#{peerAddress.port}"
              @server.connectToPeer peerAddress, 5000, (connectionErr, peer) =>
                if connectionErr?
                  @logger.debug "Failed to connect to peer at #{peerAddress.host}:#{peerAddress.port} (#{connectionErr})"
                callback()
            else
              callback()
          , (err) =>
            # This is called after the whilst condition is false
            @logger.info "Finished trying to connect to other peers (has now: #{@server.peers.length} peers)"

  tryDisconnectingPeers: ->
    @logger.info "Hunting down unresponsive peers."
    now = moment()
    unresponsivePeers = _.filter @server.peers, (peer) =>
      return false if not peer.lastMessageTimestamp?
      now.diff(peer.lastMessageTimestamp) > @options.csetella.maxPeerIdleTimeInMsec
    if unresponsivePeers? and unresponsivePeers.length > 0
      async.each unresponsivePeers, (unresponsivePeer, callback) =>
        @logger.info "Peer #{unresponsivePeer.toString()} has last sent a message #{unresponsivePeer.lastMessageTimestamp.fromNow()}. Disconnecting."
        unresponsivePeer.destroy()
        callback()
      , (err) =>
        @logger.info "Finished disconnecting unresponsive peers."
    else
      @logger.info "No unresponsive peers found."


  send: (peer, message) ->
    peer.send message
    @stats.logSentMessage message
    @emit 'msgsent', message, peer

  # Stops the node
  stop: (cb) ->
    @logger.info "Stopping CSEtella node..."

    # Stop the periodic tasks
    clearInterval task for task in @periodicTasks

    # Shutdown all the node's facilities in parallel: server, store and network monitoring
    async.parallel [
      (callback) =>
        # Disconnect from all peers
        @server.end()
        @logger.info "Sent FIN to peers." if @server.peers.length > 0
        # Stop listening
        @server.close () =>
          @logger.info "Stopped accepting new connections."
          callback()
      ,
      (callback) =>
        @monitor.stop()
        @logger.info "Stopped monitoring network."
        callback()
      ,
      (callback) =>
        @store.close (err) =>
          @logger.warn "Closing store failed: #{err.stack}" if err?
          @logger.info "Store is closed."
          callback err
    ], (err, results) =>
      cb err

  isBlacklistedPeer: (peer) ->
    _.find(@options.csetella.blacklistedPeers, (blackListedPeerAddress) ->
      if blackListedPeerAddress.host is peer.host()
        return blackListedPeerAddress.port is "*" or blackListedPeerAddress.port is peer.port()
      else
        return false
    )?

  onPeer: (joined, peer) ->
    if joined
      @logger.info "Peer connected: #{peer.toString()}"
      if @isBlacklistedPeer peer
        @logger.info "Peer #{peer.toString()} is blacklisted. Terminating connection."
        peer.end()
    else
      @logger.info "Peer disconnected #{peer.description}. Number of peers is now #{@server.peers.length}."
    @emit 'peer', joined, peer

  @_createCacheKey: (id, type) ->
    "#{id.toString('hex')}:#{type}"

  @_createCacheKeyFromMessage: (message) ->
    Node._createCacheKey message.id, message.type

  # Cache a received message
  cache: (message, peer) ->
    cacheKey = Node._createCacheKeyFromMessage(message)
    @logger.debug "Caching at #{cacheKey}: message = #{message.toString()}, peer = #{peer.toString()}"
    @messageCache.set cacheKey, peer

  # Checks whether a message is cached. Messages are cached upon their arrival to this node.
  isCached: (message) ->
    # Calling the 'get' method and not the 'has' method to update the "recently used"-ness of
    # the cached message
    not _.isUndefined @messageCache.get(Node._createCacheKeyFromMessage(message))

  # Returns the peer to which a pong/reply message should be routed back.
  # The method is trying to find a ping (query) message in the cache with the same
  # message id as the given pong (reply) message.
  findPeerToRoute: (message) ->
    assert( message.type is MessageType.pong or message.type is MessageType.reply )
    id = message.id
    type = null
    switch message.type
      when MessageType.pong then type = MessageType.ping
      when MessageType.reply then type = MessageType.query

    cacheKey = Node._createCacheKey id, type
    @logger.debug "Finding peer for cache entry: #{cacheKey}"
    peer = @messageCache.get cacheKey
    @logger.debug "Peer is: #{if peer? then peer.toString() else null}"
    return peer

  # Ping message handler
  onPing: (ping, peer) ->
    # Reply with a 'pong' message
    @monitor.getExternalAddress (err, address) => # Get the external IP address of this machine
      @logger.warn "Querying external address failed, unable to send a pong back (error: #{err})" if err?
      if not err? 
        pong = new PongMessage ping, new Address(address, @server.address().port)
        @logger.debug "Sending: #{pong.toString()} to #{peer.toString()}."
        @send peer, pong
        @forward ping, peer

  # Query message handler
  onQuery: (query, peer) ->
    # Reply with a 'reply' message
    @monitor.getExternalAddress (err, address) => # Get the external IP address of this machine
      @logger.warn "Querying external address failed, unable to send a pong back (error: #{err})" if err?
      if not err? 
        reply = new ReplyMessage query, new Address(address, @server.address().port), @options.csetella.text
        @logger.debug "Sending: #{reply.toString()} to #{peer.toString()}."
        @send peer, reply
        @forward query, peer

  _persistPeerAddress: (addressOfAPeer) ->
    # Add the address of the peer that originated the pong to
    # the node's store iff it is not this node.
    @monitor.getExternalAddress (err, address) =>
      if not err?
        if addressOfAPeer.host isnt address and addressOfAPeer.port isnt @server.address().port
          @logger.debug "Discovered peer: #{addressOfAPeer.host}:#{addressOfAPeer.port}"
          @store.addPeerAddress addressOfAPeer

  onPong: (pong, peer) ->
    
    # If the pong message doesn't contain the address, it will NOT be forwarded. However, this node
    # will not disconnect from the peer that sent it, as it might not be the culprit.
    # This is the desired behavior because it removes malformed messages from the network.
    address = pong.payloadAsAddress()
    if address instanceof Error
      @logger.warn "#{pong.toString()} from #{peer.toString()} is malformed (#{address})"
    else
      # Persist the peer that originated the pong
      @_persistPeerAddress address
      # Route the pong back to the peer that originated the ping
      @routeBack pong, peer

  onReply: (reply, peer) ->
    
    # See first comment in the onPong method.
    address = reply.payloadAsAddress()
    if address instanceof Error
      @logger.warn "#{reply.toString()} from #{peer.toString()} is malformed (#{address})"
    else
      # Persist the peer and the text
      @_persistPeerAddress address
      text = reply.payloadAsString()
      if text? and text.length > 0
        @store.addSharedText text
        @logger.debug "Text: #{text}"
        # Route the reply back to the peer that originated the query
        @routeBack reply, peer
      else
        @logger.warn "#{reply.toString()} from #{peer.toString()} is has no text."
        peer.end()

  # Forward a ping/query message from the given peer to this node's peers
  forward: (message, fromPeer) ->
    assert( message.type is MessageType.ping or message.type is MessageType.query )
    @_forwardOrRoute message, fromPeer, RouteType.forward

  # Route back a pong/reply message from the given peer to the peer that sent us a ping/query
  # with the given message's id
  routeBack: (message, fromPeer) ->
    assert( message.type is MessageType.pong or message.type is MessageType.reply )
    @_forwardOrRoute message, fromPeer, RouteType.routeBack

  # Implementation of message forwarding / routing back functionality adhering to message routing
  # rules 1 - 5 in the assignment.
  _forwardOrRoute: (message, fromPeer, routeType) ->

    assert( routeType is RouteType.forward or routeType is RouteType.routeBack )

    # Update TTL and hops
    message.hop()
    @logger.debug "Updated TTL and hops are: #{message.toString()}"

    # Message routing rule #5: if the message has been previously received on this node, avoid
    # forwarding it, unless it is of type 'pong' or 'reply', in which case, always forward.
    messageHasBeenPreviouslyReceivedOnThisNode = @isCached message
    if messageHasBeenPreviouslyReceivedOnThisNode
      @logger.debug "#{message.toString()} has been previously received at this node."
    else
      @logger.debug "Caching: #{message.toString()}"
      @cache message, fromPeer

    isAlwaysRouteMessageType = message.type is MessageType.pong or message.type is MessageType.reply
    if isAlwaysRouteMessageType
      @logger.debug "#{message.toString()} is of type that is always routed."

    # Message routing rule #4: if TTL is 0 (isDead), don't forward.
    if not message.isDead() and (isAlwaysRouteMessageType or (not messageHasBeenPreviouslyReceivedOnThisNode))
      switch routeType
        when RouteType.forward
          # Message routing rule #3: forward ping (query) messages to all directly connected
          # peers that are not the peer that sent this node the ping (query)
          for peer in @server.peers when peer isnt fromPeer
            if peer?
              @logger.debug "Forwarding #{message.toString()} to #{peer.toString()}"
              @send peer, message
        when RouteType.routeBack
          # Message routing rule #1,2: remove a pong (reply) from the network, if the
          # corresponding ping (query) has not gone through this node.
          peer = @findPeerToRoute message
          if peer? and _.contains(@server.peers, peer)
            @logger.debug "Routing #{message.toString()} back to #{peer.toString()}."
            @send peer, message
          else
            @logger.debug "Peer was not found when trying to route #{message.toString()} from #{fromPeer.toString()}."

  # Returns a JSON with the status of the node
  status: (cb)->
    @store.status (err, storeStatus) =>
      cb err, {
        "uptime": @stats.startedOn.fromNow(true),
        "sent": @stats.sent,
        "received": @stats.received,
        "server" : @server.toJSON(),
        "store": storeStatus }


###
class CSEtellaApplication
Enacapsulates the CSEtella application which includes the CSEtella node and
a web server which provides information about the node.
###
class CSEtellaApplication extends Application

  constructor: ->
    super

    # The CSEtella Node
    @node = new Node @config, @logger

    # The Crawler
    @crawler = new Crawler @logger, @config.crawler
    
    # The Web Server/Web Application to monitor the node
    @webserver = express()
    @webserver.use express.static(path.normalize(path.join(__dirname, '/../web/public')))

    # Dashboard Page
    @webserver.get '/status', (req, res) =>
      @node.status (err, status) =>
        if err?
          res.send 500, { "error": err }
        else
          res.send status

    # Topology Page
    @webserver.get '/topology', (req, res) =>
      res.send @crawler.topology

  interrupt: ->
    @node.stop () =>
      super

  sigterm: ->
    @node.stop () =>
      super

  run: ->
    @node.start (err) =>
      
      if err?
        @logger.error "CSEtella node failed to start, terminating."
        process.exit -1

      # Node started successfully
      @webserver.listen @config.webserver.port
      @crawler.start()
    

###
Entry Point
###
if module is require.main
  global.application = new CSEtellaApplication
  global.application.start()


###
Exports
###
exports.NodeStore = NodeStore
exports.Node = Node
exports.CSEtellaApplication = CSEtellaApplication