#!/bin/bash
read -p "Target IP: " target_ip
read -p "Start port: " start_port
read -p "End port: " end_port
echo "scanning ${target_ip} on ports ${start_port} thru ${end_port}" > scan_result
for ((i=${start_port};i<=${end_port};i++)); do
	timeout 1.5 echo -n 2>/dev/null < /dev/tcp/${target_ip}/${i} && echo "port ${i} open" >> scan_result || echo "port ${i} closed" >> scan_result &
	if [[ $(expr ${i} % 1000) -eq 0 ]]; then
		echo "scanning ${target_ip} port ${i} of ${end_port}"
	fi
done
sleep 1.5
grep -P -e "scan|open" scan_result