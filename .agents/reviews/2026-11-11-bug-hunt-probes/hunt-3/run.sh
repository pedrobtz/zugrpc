#!/bin/sh
# usage: run.sh probe.R [port]   -- starts a fresh h2srv, runs the probe, kills the server
W=<W>/hunt-3
P=${2:-47330}
B=$(basename "$1" .R)
"$W/h2srv" -port "$P" -log "$W/$B.srvlog" > /dev/null 2>&1 &
SP=$!
sleep 0.4
H3_PORT=$P H3_LOG="$W/$B.srvlog" Rscript "$W/$1" > "$W/$B.out" 2>&1
echo "exit=$?" >> "$W/$B.out"
sleep 0.3
kill $SP 2>/dev/null
cat "$W/$B.out"
