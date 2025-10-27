#!/bin/bash
erl -pa build/dev/erlang/*/ebin \
    -sname engine@localhost \
    -setcookie test_cookie \
    -run reddit_sim main -- server
