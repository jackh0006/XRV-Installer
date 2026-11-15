# XRV v1.2.2 — smart client relay-port selection

The client installer no longer assumes that every server uses TCP 8443.

When you enter only a domain or IP address, it checks XRV's familiar public
HTTPS ports for the `/healthz` endpoint, shows any healthy port it finds, then
asks you to confirm or change the port before writing configuration. If no
endpoint answers, it requires an explicit choice and offers to retry a changed
port instead of silently continuing with a dead default.

For the current example server, entering `g.mhhdns.online` detects and offers
TCP `10443`.
