#!/usr/bin/env bash

git clean -d -x -f

git reset --hard

git pull

git gc
