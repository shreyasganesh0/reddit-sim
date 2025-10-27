#!/bin/bash

cd reddit-codegen
./generate.sh
cd ../reddit-sim
gleam clean
gleam build
