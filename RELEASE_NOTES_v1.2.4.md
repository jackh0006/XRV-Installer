# XRV v1.2.4 — safe port 80 service detection

XRV now resolves a process listening on TCP port 80 to the active systemd
service that owns it. For example, a `hedioum-tunnel` listener is shown as
`hedioum.service`.

When a new Let's Encrypt HTTP-01 certificate is required, XRV asks before it
temporarily stops that exact service. It restarts every service it stopped,
even when certificate issuance fails, and saves the matching renewal hooks only
after success. Choosing No exits without stopping the service.

This fixes certificate setup on servers where an unrelated tunnel owns port 80.
It does not remove, edit, or restart an existing HAProxy configuration.
