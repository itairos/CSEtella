###
csetella-node.coffee

Unit Test Module for the Node class.

Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
###


###
Dependencies
###
fs = require 'fs'
path = require 'path'
should = require 'should'
winston = require 'winston'
uuid = require 'node-uuid'
_ = require 'underscore'
async = require 'async'
{ NodeStore, Node, CSEtellaApplication } = require '../src/csetella-node'
{ MessageType, Message, PingMessage, QueryMessage } = require '../src/csetella'

# Set up a test logger
level = process.env['level']
level ?= 'warn'
logger = new winston.Logger { transports: [ new winston.transports.Console({ 'colorize': true, 'level': level }) ] }
# Set up test configuration
filename = process.env['config']
filename ?= path.join __dirname, 'test-config.json'

# Helpers
removeDirectory = (directoryPath) ->
  files = []
  if fs.existsSync directoryPath
    files = fs.readdirSync directoryPath
    files.forEach (file, index) ->
      filePath = path.join directoryPath, file
      if fs.statSync(filePath).isDirectory()
        removeDirectory filePath
      else
        fs.unlinkSync filePath
    fs.rmdirSync directoryPath

createConfigForNode = (nodeIndex)->
  config = JSON.parse fs.readFileSync(filename)
  basePort = config.csetella.preferredPort
  config.csetella.preferredPort = basePort + nodeIndex
  config.csetella.text = "#{nodeIndex}"
  config.storage.location = "#{config.storage.location}-#{nodeIndex}"

  if nodeIndex is 0
    config.csetella.knownPeers = []
  else
    config.csetella.knownPeers = [ { "host": "localhost", "port": basePort } ]
  return config

createNodes = (howMany)->
  nodes = []
  nodes.push new Node(createConfigForNode(i), logger) for i in [0...howMany]
  return nodes

describe 'csetella-node', ->

  describe 'store', ->

    store = null
    beforeEach (done) ->
      storePath = "./.testdb"
      removeDirectory storePath
      store = new NodeStore(new winston.Logger, storePath, done)

    afterEach (done) ->
      store.close done

    it 'should be able to store text and read it', (done) ->
      async.times 100, (n, next) ->
        text = uuid.v4()
        store.addSharedText text, (err) ->
          next err, text
      , (err, texts) ->
        should.not.exist err
        store.getAllSharedTexts (err, textsFromStore) ->
          _.difference(texts, textsFromStore).should.be.empty
          done()

    it 'should be able to store peers and read them. peers should be sorted', (done) ->
      async.times 100, (n, next) ->
        port = _.random 0, 65535
        host = "#{_.random(0, 255)}.#{_.random(0, 255)}.#{_.random(0, 255)}.#{_.random(0, 255)}"
        peer = { "port": port, "host": host, toString: () ->
          "#{@host}:#{@port}"
        }
        store.addPeer peer, (err) ->
          next err, peer.toString()
      , (err, peers) ->
        should.not.exist err
        store.getPeers (err, peersFromStore) ->
          should.not.exist err
          # Ignore order for now
          peersFromStore = _.map peersFromStore, (peer) ->
            "#{peer.host}:#{peer.port}"
          _.difference(peers, peersFromStore).should.be.empty
          done()

  describe '2 nodes', ->
    nodes = null
    beforeEach (done) ->
      @timeout 5000
      nodes = createNodes(2)
      should.exist nodes
      async.each nodes, (node, callback) ->
        node.once 'peer', (joined, peer) ->
          callback() if joined
        node.start (err) ->
          should.not.exist err
      , (err) ->
        done err

    afterEach (done) ->
      async.each nodes, (node, callback) ->
        node.stop callback
      , (err) ->
        done err

    it 'should be able to send a ping and receive a pong', (done) ->
      # Make sure peers are connected to each other
      nodes[0].server.peers.length.should.equal 1
      nodes[1].server.peers.length.should.equal 1
      # These are the ping messages send from 0 to 1 and from 1 to 0 respectively
      ping1 = new PingMessage { ttl: 1 }
      ping2 = new PingMessage { ttl: 1 }
      # 3. node 1 receives a pong from node 0
      nodes[1].on 'msgrecv', (pong2, peer) ->
        if pong2.type is MessageType.pong
          Message.AreBuffersEqual(pong2.id, ping2.id).should.be.true
          pong2.payloadAsAddress().port.should.equal nodes[0].server.address().port
          done()

      # 2. node 0 receives the pong from node 1. node 1 then pings node 0 (ping2)
      nodes[0].on 'msgrecv', (pong, peer) ->
        if pong.type is MessageType.pong
          Message.AreBuffersEqual(pong.id, ping1.id).should.be.true
          pong.payloadAsAddress().port.should.equal nodes[1].server.address().port
          nodes[1].server.peers[0].send ping2
      # 1. node 0 pings node 1
      nodes[0].server.peers[0].send ping1

    it 'should be able to send a query and receive a reply', (done) ->
      # Make sure peers are connected to each other
      nodes[0].server.peers.length.should.equal 1
      nodes[1].server.peers.length.should.equal 1
      # These are the query messages send from 0 to 1 and from 1 to 0 respectively
      q1 = new QueryMessage { ttl: 1 }
      q2 = new QueryMessage { ttl: 1 }
      # 3. node 1 receive a reply from node 0
      nodes[1].on 'msgrecv', (r2, peer) ->
        if r2.type is MessageType.reply
          Message.AreBuffersEqual(r2.id, q2.id).should.be.true
          r2.payloadAsString().should.be.equal "0" # Each node sends their node index as their text
          r2.payloadAsAddress().port.should.equal nodes[0].server.address().port
          done()

      # 2. node 0 receives the reply from node 1. node 1 then queries node 0 (q2)
      nodes[0].on 'msgrecv', (r1, peer) ->
        if r1.type is MessageType.reply
          Message.AreBuffersEqual(r1.id, q1.id).should.be.true
          r1.payloadAsString().should.be.equal "1" # Each node sends their node index as their text
          r1.payloadAsAddress().port.should.equal nodes[1].server.address().port
          nodes[1].server.peers[0].send q2
      # 1. node 0 queries node 1
      nodes[0].server.peers[0].send q1

  describe '3 nodes (star topology)', ->
    nodes = null
    beforeEach (done) ->
      @timeout 5000
      # Creates 3 nodes, node[0] is the "known peer" and the 2 other nodes connect to it.
      nodes = createNodes(3)
      nodes.length.should.equal 3
      should.exist nodes
      async.each nodes, (node, callback) ->
        node.on 'peer', (joined, peer) ->
          if joined # Make sure this was called because a peer connected (If a peer disconnects, 'joined' is false)
            # If this is node[0], call the callback only after the 2nd peer is connected
            if node is nodes[0] and node.server.peers.length is 2
              callback()
            else if node isnt nodes[0]
              callback()

        node.start (err) ->
          should.not.exist err
      , (err) ->
        if not err?
          # Make sure peers are connected to each other
          nodes[0].server.peers.length.should.equal 2
          nodes[1].server.peers.length.should.equal 1
          nodes[2].server.peers.length.should.equal 1
        done err

    afterEach (done) ->
      async.each nodes, (node, callback) ->
        node.stop callback
      , (err) ->
        done err

    it 'should be able to forward pings and route them back to the originating node', (done) ->
      # node 1 pings node 0, but should receive 2 pongs (from node 0 and from node 2)
      ping = new PingMessage
      numberOfPongsReceivedByNode1 = 0
      nodes[1].on 'msgrecv', (message, peer) ->
        if message.type is MessageType.pong and Message.AreBuffersEqual(message.id, ping.id)
          numberOfPongsReceivedByNode1++
          if numberOfPongsReceivedByNode1 is 2
            done()

      nodes[1].send nodes[1].server.peers[0], ping

    it 'should be able to forward queries and route them back to the originating node', (done) ->
      # node 1 queries node 0, but should receive 2 replies (from node 0 and from node 2)
      query = new QueryMessage
      numberOfRepliesReceivedByNode1 = 0
      nodes[1].on 'msgrecv', (message, peer) ->
        if message.type is MessageType.reply and Message.AreBuffersEqual(message.id, query.id)
          numberOfRepliesReceivedByNode1++
          if numberOfRepliesReceivedByNode1 is 2
            done()

      nodes[1].send nodes[1].server.peers[0], query
