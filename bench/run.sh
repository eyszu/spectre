#!/usr/bin/env bash
# Single-core comparison: each server is pinned to CPU 0 and wrk to CPU 1.
# Usage: bench/run.sh [seconds] [connections]
set -euo pipefail
cd "$(dirname "$0")"
DUR=${1:-8}; CONN=${2:-32}
mkdir -p out
crystal build --release --no-debug -o out/spectre_server spectre_server.cr
(cd go_server && go build -o ../out/go_server .)

run() { # name, server command...
  local name=$1; shift
  PORT=3999 GOMAXPROCS=1 taskset -c 0 "$@" >/dev/null 2>&1 &
  local pid=$!
  sleep 1
  echo "== $name"
  for scenario in "GET /|http://127.0.0.1:3999/|" "GET /users/:id (JSON)|http://127.0.0.1:3999/users/42|" "POST /people (typed JSON in/out)|http://127.0.0.1:3999/people|-s post.lua"; do
    IFS='|' read -r label url extra <<<"$scenario"
    taskset -c 1 wrk -t1 -c"$CONN" -d2s $extra "$url" >/dev/null   # warm-up
    out=$(taskset -c 1 wrk -t1 -c"$CONN" -d"${DUR}s" --latency $extra "$url")
    rps=$(awk '/Requests\/sec/{print $2}' <<<"$out")
    p50=$(awk '/ 50%/{print $2}' <<<"$out"); p99=$(awk '/ 99%/{print $2}' <<<"$out")
    printf "  %-34s %10s req/s   p50 %-8s p99 %s\n" "$label" "$rps" "$p50" "$p99"
  done
  kill $pid; wait $pid 2>/dev/null || true
}
run "Spectre (Crystal, 1 core)" out/spectre_server
run "Go net/http (1 core)" out/go_server
