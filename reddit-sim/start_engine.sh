#!/bin/bash

METRICS_IP=${1:-"localhost"} # Default to 1000 if no argument is provided
NUM_USERS=${2:-10} # Default to 1000 if no argument is provided
IP=${3:-"localhost"} # Default to 1000 if no argument is provided

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: ./start_engine.sh <metrics_ip> <num_users> <ip>"
    echo "No <num_users> provided, defaulting to ip: $IP, metrics_ip: $METRICS_IP, num_users: $NUM_USERS"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname engine@$IP \
    -setcookie test_cookie \
    -s reddit_sim main -- server $METRICS_IP $NUM_USERS $IP
