#!/bin/bash

NUM_USERS=${1:-1000}   # Default to 1000 if no 1st argument
RUN_TIME=${2:-60000}   # Default to 60000ms if no 2nd argument

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./start_client.sh <num_users> <run_time_ms>"
    echo "Defaulting to $NUM_USERS users for $RUN_TIME ms"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname client@localhost \
    -setcookie test_cookie \
    -s reddit_sim main -- client simulator $NUM_USERS $RUN_TIME
