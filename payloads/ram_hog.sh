#!/usr/bin/env bash
# Pins growing blocks of memory until the machine runs out of RAM

chunk=$(printf '%1048576s' x)
chunks=()
while :; do
    chunks+=("$chunk")
done
