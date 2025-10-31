#!/bin/bash
erl -pa build/dev/erlang/*/ebin \
    -sname client@localhost \
    -setcookie test_cookie \
    -run reddit_sim main -- client simulator 1000
