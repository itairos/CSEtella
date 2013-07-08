/*
index.js
Implementation of a CSEtella node controller (as in MVC) for the web application
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
*/

function addCommasToNumber(n) {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function CSEtellaNodeController ($scope, $timeout, $http) {
  var poll = function () {
    $http.get('/status').success(function (data) {

      // Calculate Sent/Received Totals
      data.totalSent = addCommasToNumber(data.sent.pings + data.sent.pongs + data.sent.queries
        + data.sent.replies);
      data.totalReceived = addCommasToNumber(data.received.pings + data.received.pongs + 
        data.received.queries + data.received.replies);

      // Format Message Totols
      data.sent.pings = addCommasToNumber(data.sent.pings);
      data.received.pings = addCommasToNumber(data.received.pings);

      data.sent.pongs = addCommasToNumber(data.sent.pongs);
      data.received.pongs = addCommasToNumber(data.received.pongs);

      data.sent.queries = addCommasToNumber(data.sent.queries);
      data.received.queries = addCommasToNumber(data.received.queries);

      data.sent.replies = addCommasToNumber(data.sent.replies);
      data.received.replies = addCommasToNumber(data.received.replies);

      $scope.nodeStatus = data;
      $timeout(poll, 5000);
    });
  }
  poll();
}