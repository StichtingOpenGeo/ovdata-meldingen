#!/bin/sh
#
# Surfaces Flarum's own log to the container's stdout.
#
# Flarum logs through Monolog's rotating handler, into
# storage/logs/flarum-YYYY-MM-DD.log — a file inside the container, on a
# volume, that "docker compose logs" never sees. Application errors, including
# every mail failure, land there and nowhere else. Without this you get a forum
# that reports an error with no trace of it anywhere you would think to look.
#
# The filename changes at midnight, so re-point tail when a newer file appears.
LOGDIR=/flarum/app/storage/logs
current=""
pid=""

while :; do
    newest="$(ls -1t "$LOGDIR"/flarum-*.log 2>/dev/null | head -n 1)"
    if [ -n "$newest" ] && [ "$newest" != "$current" ]; then
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        # -n0: only what is written from now on, so a restart does not replay
        # the whole day.
        tail -n0 -F "$newest" &
        pid=$!
        current="$newest"
    fi
    sleep 15
done
