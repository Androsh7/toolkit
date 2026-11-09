#!/usr/bin/env bash
# Pins growing blocks of memory across multiple worker processes until the machine runs out of RAM

worker_count=$(nproc 2>/dev/null || echo 4)

if [ "${1:-}" = "worker" ]; then
    chunk=$(printf '%1048576s' x)
    chunks=()
    while :; do
        chunks+=("$chunk")
    done
else
    echo "Spawning ${worker_count} memory hog workers (Ctrl+C to stop)..."
    worker_pids=()
    stop_workers() {
        for worker_pid in "${worker_pids[@]}"; do
            kill "$worker_pid" 2>/dev/null
        done
        wait 2>/dev/null
    }
    trap stop_workers EXIT INT TERM
    for worker_number in $(seq "$worker_count"); do
        bash "$0" worker &
        worker_pids+=("$!")
    done
    while :; do
        sleep 1
        total_memory_kb=0
        for worker_pid in "${worker_pids[@]}"; do
            worker_rss_kb=$(ps -o rss= -p "$worker_pid" 2>/dev/null | tr -d ' ')
            if [ -n "$worker_rss_kb" ]; then
                total_memory_kb=$((total_memory_kb + worker_rss_kb))
            fi
        done
        echo "Workers: $(jobs -pr | wc -w) alive, holding $((total_memory_kb / 1024)) MB"
    done
fi
