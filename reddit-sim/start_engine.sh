#!/bin/bash

NUM_USERS=${1:-1000} # Default to 1000 if no argument is provided

if [ -z "$1" ]; then
    echo "Usage: ./start_engine.sh <num_users>"
    echo "No <num_users> provided, defaulting to $NUM_USERS"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname engine@localhost \
    -setcookie test_cookie \
    -s reddit_sim main -- server $NUM_USERS
