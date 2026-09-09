#!/usr/bin/env bash
read -p "Remote host: " host
read -p "Remote port: " port

# open bidirectional fd 3
exec 3<>/dev/tcp/$host/$port || { echo "connect to ${host}:${port} failed"; exit 1; }

# determine our ephemeral local port
local_port=$(ss -tanp 2>/dev/null | awk -v h="$host:$port" '$1=="ESTAB" && $5==h {split($4,a,":"); print a[length(a)]}' | head -n1)
[[ -z "$local_port" ]] && local_port="??"

# cleanup on exit
cleanup() {
  exec 3>&- 3<&-
  [[ -n "$reader_pid" ]] && kill "$reader_pid" 2>/dev/null
}
trap cleanup EXIT INT

# background reader
while IFS= read -r line <&3; do
  printf '%s:%s> %s\n' "$host" "$port" "$line"
done &
reader_pid=$!

echo "connected to $host:$port"
echo "type messages to send. '/quit' to exit."

# small helper: move cursor up 1 line + clear that line
move_up_and_clear() {
  if command -v tput >/dev/null 2>&1; then
    tput cuu1   # up 1 line
    tput cr     # to column 0
    tput el     # clear to end of line
  else
    printf '\033[1A\r\033[2K'  # ANSI fallback
  fi
}

# main loop
while IFS= read -r userline; do
  [[ "$userline" == "/quit" ]] && break

  # clear the user entered line, and reprint it with the RHP
  move_up_and_clear
  printf '127.0.0.1:%s> %s\n' "$local_port" "$userline"

  # transmit the data to the remote host
  printf '%s\r\n' "$userline" >&3
done

cleanup