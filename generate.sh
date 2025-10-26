#!/bin/bash

rm src/generated/*
gleam run --module generator/config_parser
