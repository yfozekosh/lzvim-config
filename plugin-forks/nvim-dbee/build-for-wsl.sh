#!/bin/bash

ISNTALL_PATH=/mnt/c/__Projects/
NAME=dbee.exe
PATH_TO_EXE="$ISNTALL_PATH$NAME"

pushd ./dbee/
GOOS=windows GOARCH=amd64 CGO_ENABLED=1 go build -C ./ -o $ISNTALL_PATH
popd
