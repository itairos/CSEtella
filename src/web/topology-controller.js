/*
topology-controller.js
Implementation of a CSEtella topology controller (as in MVC) for the web application
Itai Rosenberger (itairos@cs.washington.edu)

CSEP552 Assignment #3
http://www.cs.washington.edu/education/courses/csep552/13sp/assignments/a3.html
*/

function CSEtellaTopologyController ($scope, $timeout, $http) {
  var poll = function () {
    $http.get('/topology').success(function (data) {
      $scope.topology = data;
      if (data.nodes.length == 0) {
        $timeout(poll, 5000);
      }
    });
  }
  poll();
}