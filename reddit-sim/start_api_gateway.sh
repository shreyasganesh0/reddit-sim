#!/bin/bash

IP=${1:-"localhost"} # Default to 1000 if no argument is provided
ENGINE_IP=${2:-"localhost"} # Default to 1000 if no argument is provided

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: ./start_engine.sh <metrics_ip> <num_users> <ip>"
    echo "No <num_users> provided, defaulting to ip: $IP, engine_ip $ENGINE_IP"
    echo ""
fi

erl -pa build/dev/erlang/*/ebin \
    -sname apigateway@$IP \
    -setcookie test_cookie \
    -s reddit_sim main -- api_gateway $IP $ENGINE_IP
