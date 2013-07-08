#!/usr/bin/env bash

echo
echo "Node.js Installer"
echo "For support, please contact itairos@cs.washington.edu."
echo

if [ "$(uname)" != "Linux" ]; then
  echo "Are you running me from OS X? Please run me from Ubuntu."
  exit 1
fi

if [ "$(id -u)" != "0" ]; then
  echo "Did you forget to run me with sudo?"
  exit 1
fi

function run {
    "$@"
    s=$?
    if [ $s -ne 0 ]; then
        echo "Failed running '$@'"
        exit $s
    fi
    return $s
}

echo "Installing Node.js..."
run sudo apt-get -y -qq install python-software-properties
run sudo add-apt-repository -y ppa:chris-lea/node.js > /dev/null 2>&1
run sudo apt-get -y -qq update
run sudo apt-get -y -qq install nodejs build-essential
echo "You're good to go!"