#!/bin/sh
# cups-pdf's own package postinst normally registers its "PDF" queue, but
# that hook fires at package-install time — during `docker build`, cupsd
# isn't actually running, so the registration may silently not happen.
# Register it explicitly here at container startup instead, once cupsd is
# confirmed up, and skip it if it's already there (e.g. a future base
# image where the package hook *did* take effect).
set -e

/usr/sbin/cupsd -f &
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
    DRIVER=$(lpinfo -m | grep -i 'cups-pdf' | head -1 | cut -d' ' -f1)
    if [ -z "$DRIVER" ]; then
        echo "No cups-pdf driver found via lpinfo -m; falling back to a raw queue." >&2
        lpadmin -p PDF -v cups-pdf:/ -E
    else
        lpadmin -p PDF -v cups-pdf:/ -m "$DRIVER" -E
    fi
    cupsenable PDF
    cupsaccept PDF
else
    echo "PDF printer already registered."
fi

wait "$CUPSD_PID"
