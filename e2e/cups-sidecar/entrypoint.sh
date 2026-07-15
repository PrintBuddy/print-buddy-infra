#!/bin/sh
# cups-pdf's own package postinst normally registers its "PDF" queue, but
# that hook fires at package-install time — during `docker build`, cupsd
# isn't actually running, so the registration may silently not happen.
# Register it explicitly here at container startup instead, once cupsd is
# confirmed up, and skip it if it's already there (e.g. a future base
# image where the package hook *did* take effect).
set -e

# Docker defaults RLIMIT_NOFILE to ~1M, but CUPS's client code (lpstat,
# lpadmin, ...) still uses select() internally with a fixed-size fd_set
# (FD_SETSIZE, typically 1024) — any fd number the kernel happens to hand
# out at or above 1024 makes select() fail with EBADF, surfacing as
# "Unable to connect to server: Bad file descriptor". Capping the limit
# back down keeps every fd CUPS opens under that ceiling. (This is the
# real cause of the intermittent "Bad file descriptor" failures seen
# earlier on lpinfo/lpadmin — not a stdin/job-control issue as first
# suspected.)
ulimit -n 1024

# Redirect stdin from /dev/null: without a TTY (the normal case under
# `docker compose`, unlike an interactive `docker run`), backgrounding a
# job in dash/sh with a stdin tied to a non-TTY can leave that fd in a
# state that breaks *later* foreground commands in this same script —
# giving cupsd its own explicit stdin avoids it inheriting/holding onto
# the script's.
/usr/sbin/cupsd -f < /dev/null &
CUPSD_PID=$!

echo "Waiting for cupsd to accept connections..."
for i in $(seq 1 30); do
    if lpstat -r >/dev/null 2>&1; then
        echo "cupsd is up."
        break
    fi
    sleep 1
done

if ! lpstat -p PDF >/dev/null 2>&1; then
    echo "Registering the PDF virtual printer..."
    # A raw queue (no -m driver) is enough: CUPS + the cups-pdf backend
    # still process and complete jobs through it (verified against a real
    # job end-to-end), and `lpinfo -m`'s driver-database lookup was
    # unreliable in this container (consistently "Bad file descriptor"
    # regardless of stdin handling) — not worth chasing further for a
    # throwaway CI printer.
    lpadmin -p PDF -v cups-pdf:/ -E </dev/null
    cupsenable PDF
    cupsaccept PDF
else
    echo "PDF printer already registered."
fi

wait "$CUPSD_PID"
