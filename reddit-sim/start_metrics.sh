#!/bin/bash
erl -pa build/dev/erlang/*/ebin \
    -sname metrics@localhost \
    -setcookie test_cookie \
    -run reddit_sim main -- metrics 
