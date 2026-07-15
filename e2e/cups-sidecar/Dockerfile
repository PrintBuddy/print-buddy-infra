# Minimal CUPS server exposing only a virtual PDF printer — lets E2E tests
# submit and complete real print jobs through the real CUPS pipeline
# without ever reaching a physical printer. entrypoint.sh registers the
# "PDF" queue explicitly at startup (see its comment for why); backend's
# printer_updater scheduler job then picks it up and auto-creates the
# matching Printer DB row the first time it's seen (see
# db/crud/printer.py's update_printer_CUPS).
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        cups \
        cups-pdf \
    && rm -rf /var/lib/apt/lists/*

# Listen on the network — default CUPS only binds localhost/socket, but
# the backend container needs to reach this one over the compose network.
# ServerAlias * is required too: modern CUPS rejects requests whose HTTP
# Host header isn't a recognized alias (DNS-rebinding protection), and the
# backend reaches this container via its Docker Compose service name
# ("cups-sidecar"), not "localhost". The two `Order allow,deny` lines
# below are exactly (and only) the top-level `<Location />`/`<Location
# /admin>` blocks — everything else in the stock config uses `Order
# deny,allow`, so this precisely targets those two without duplicating
# blocks. This is a throwaway, network-isolated CI sidecar with no auth,
# never exposed beyond the compose network.
RUN sed -i \
        -e 's/^Listen localhost:631/Port 631\nServerAlias */' \
        -e 's/^Browsing .*/Browsing Off/' \
        -e '/Order allow,deny/a\  Allow all' \
        /etc/cups/cupsd.conf

# cups-pdf's default `Out ${HOME}/PDF` resolves the submitting job's
# owner (here, the backend container's "appuser") to a home directory on
# *this* container's own system — which doesn't have that user, so
# ${HOME} resolution fails and jobs never leave PENDING. Fixed output
# path sidesteps needing the submitting user to exist here at all.
RUN mkdir -p /tmp/cups-pdf && chmod 1777 /tmp/cups-pdf \
    && sed -i 's|^Out .*|Out /tmp/cups-pdf|' /etc/cups/cups-pdf.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 631

CMD ["/entrypoint.sh"]
