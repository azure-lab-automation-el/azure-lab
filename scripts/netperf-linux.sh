#!/usr/bin/env bash
# Runs ON esther-linux-01 (Sweden). Free network measurements: TCP connect latency to the Israel servers, GitHub latency/throughput,
# and a temporary HTTP server on port 1270 (already allowed from 10.77.0.0/16, SCX agent not installed yet) so the DC can measure Israel<-Sweden throughput.
set -u
tcpms() { local h=$1 p=$2 s e; s=$(date +%s%N); timeout 3 bash -c "exec 3<>/dev/tcp/$h/$p" 2>/dev/null && { e=$(date +%s%N); echo $(( (e-s)/100000 )); } || echo fail; }
for t in 10.77.1.10:5985 10.77.1.4:5985 10.77.1.10:445; do h=${t%:*}; p=${t#*:}; v=""; for i in $(seq 1 10); do v="$v $(tcpms $h $p)"; done; echo "tcp_connect_x0.1ms $t:$v"; done
ping -c 5 -W 2 10.77.1.10 | tail -2
for u in https://api.github.com/zen https://github.com/ https://codeload.github.com/; do curl -s -o /dev/null -w "gh $u dns=%{time_namelookup} connect=%{time_connect} tls=%{time_appconnect} ttfb=%{time_starttransfer} total=%{time_total}\n" "$u"; done
url=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | grep -o 'https://[^"]*actions-runner-linux-x64-[0-9.]*\.tar\.gz' | head -1)
curl -sL -o /dev/null -w "gh_download $url size=%{size_download} time=%{time_total} speed_Bps=%{speed_download}\n" "$url"
head -c 209715200 /dev/urandom > /tmp/np.bin
cd /tmp && nohup setsid timeout 300 python3 -m http.server 1270 --bind 10.78.1.20 >/tmp/np.log 2>&1 &
sleep 2; echo "HTTP_1270_UP=$(ss -ltn | grep -c ':1270 ')"; echo NETPERF_LINUX_DONE
