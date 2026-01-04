read -p "First 3 octets of the IP (e.g., 192.168.1): " ip_base
for i in {1..254} ;do (ping -c 1 $ip_base.$i | grep "bytes from" &) ;done