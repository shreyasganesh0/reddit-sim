#!/bin/bash

# This should match the number of users the engine and metrics are expecting
NUM_USERS=${1:-1000} # Default to 1000 if no argument is provided

if [ -z "$1" ]; then
    echo "Usage: ./start_metrics.sh <num_users>"
    echo "No <num_users> provided, defaulting to $NUM_USERS"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname metrics@localhost \
    -setcookie test_cookie \
    -s reddit_sim main -- metrics $NUM_USERS

