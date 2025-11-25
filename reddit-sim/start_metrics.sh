#!/bin/bash

# This should match the number of users the engine and metrics are expecting
ENGINE_IP=${1:-"localhost"} # Default to 1000 if no argument is provided
NUM_USERS=${2:-10} # Default to 1000 if no argument is provided
IP=${3:-"localhost"} # Default to 1000 if no argument is provided

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: ./start_metrics.sh <num_users>"
    echo "No <num_users> provided, defaulting to ip: $IP, engine ip: $ENGINE_IP, num_users: $NUM_USERS"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname metrics@$IP \
    -setcookie test_cookie \
    -s reddit_sim main -- metrics $ENGINE_IP $NUM_USERS $IP

