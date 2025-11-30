#!/bin/bash

METRICS_IP=${1:-"localhost"}   # Default to 60000ms if no 2nd argument
ENGINE_IP=${2:-"localhost"}   # Default to 60000ms if no 2nd argument
NUM_USERS=${3:-10}   # Default to 1000 if no 1st argument
RUN_TIME=${4:-60000}   # Default to 60000ms if no 2nd argument
IP=${5:-"localhost"}   # Default to 60000ms if no 2nd argument

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ]; then
    echo "Usage: ./start_client.sh <num_users> <run_time_ms>"
    echo "Defaulting to ip: $IP, metrics ip: $METRICS_IP, engine ip: $ENGINE_IP with $NUM_USERS users for $RUN_TIME ms"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname client@$IP \
    -setcookie test_cookie \
    -s reddit_sim main -- client $METRICS_IP $ENGINE_IP $NUM_USERS $RUN_TIME $IP
