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
# This is a throwaway, network-isolated CI sidecar with no auth, never
# exposed beyond that network.
RUN sed -i \
        -e 's/^Listen localhost:631/Port 631/' \
        -e 's/^Browsing .*/Browsing Off/' \
        /etc/cups/cupsd.conf \
    && printf '<Location />\n  Order allow,deny\n  Allow all\n</Location>\n<Location /admin>\n  Order allow,deny\n  Allow all\n</Location>\n' >> /etc/cups/cupsd.conf

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 631

CMD ["/entrypoint.sh"]
