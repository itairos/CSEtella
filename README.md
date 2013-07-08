CSEtella
=

CSEtella is a P2P node adhering to the [CSEtella protocol] [1]. It is very similar to the [Gnutella protocol] [2].

The node has the following main features:

* **High Performance**: the node can process over 1000 messages/second (on a quad core Intel Xeon 2.8Ghz).
* **Crawler**: the node can crawl (using [breadth first search]) the P2P network and discover the peers and their topology.
* **Web Frontend**: view live stats of the node and the topology produced by the crawler.
* **Auto discovery of the node's external IP** useful when the node runs behind a NAT.
* **Configurable**: the behavior of the node is highly configurable via a JSON file. A user can set peer limits, timeouts, blacklist peers, craweling behavior and more.

Version
-

0.0.1

Tech 
-

CSEtella uses a number of open source projects to work properly:

* [CoffeeScript] - a programming language that transcompiles to JavaScript.
* [node.js] - evented I/O in JavaScript.
* [LevelDB] - a fast key value storage library by Google.
* A bunch of node.js modules. Notably: [async], [lru-cache], [underscore.js], [moment.js]. Check out package.json for the full list.
* [Express] - fast node.js network app framework [@tjholowaychuk]
* [Bootstrap] - UI boilerplate for modern web apps by Twitter.
* [jQuery] - A popular JavaScript library [@jeresig].
* [Angular.js] - An MVC JavaScript library by Google.
* [d3.js] - A JavaScript visualization library.

Installation
-

TODO

Screenshots
-
### Topology 1
![Topology1](http://i.imgur.com/2vmedjk.png)

### Topology 2
![Topology2](http://i.imgur.com/Xna9jlz.png)

### Web Frontend
![Web1](http://i.imgur.com/4NuhpJU.png)

![Web2](http://i.imgur.com/Jn70bQ5.png)

![Web3](http://i.imgur.com/4JculN7.png)

License
-

Code: [WTFPL]
Images: free for non commercial use (license can be found [here] [Futurama License]).



  [1]: http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
  [2]: http://rfc-gnutella.sourceforge.net/
  
  [async]: https://github.com/caolan/async
  [lru-cache]: https://github.com/isaacs/node-lru-cache
  [underscore.js]: http://underscorejs.org
  [moment.js]: http://momentjs.com
  [CoffeeScript]: http://coffeescript.org
  [node.js]: http://nodejs.org
  [LevelDB]: https://code.google.com/p/leveldb/
  [Bootstrap]: http://twitter.github.com/bootstrap/
  [jQuery]: http://jquery.com  
  [@tjholowaychuk]: http://twitter.com/tjholowaychuk
  [express]: http://expressjs.com
  [Angular.js]: http://angularjs.org
  [d3.js]: http://d3js.org
  [WTFPL]: http://www.wtfpl.net
  [breadth first search]: https://en.wikipedia.org/wiki/Breadth-first_search
  [Futurama License]: http://pixelpirate.deviantart.com/art/Futurama-175960105
  [@jeresig]: https://twitter.com/jeresig
