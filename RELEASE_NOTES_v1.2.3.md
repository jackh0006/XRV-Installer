# XRV v1.2.3 — Google setup from the VPS

The VPS completion screen now gives the exact commands to read Code.gs and
the tunnel key, followed by Google deployment, client setup, verification and
troubleshooting steps. The guide is saved as /etc/xrv/GOOGLE-SETUP.txt and
can also be printed with --google-guide.

Both generated forwarders use documented fetch options, explicitly validate
TLS certificates, omit private upstream error details, and skip storage reads
when invocation counting is disabled. The encrypted payload protocol is
unchanged. Automated tests exercise both templates using mocked Google services.

Existing Google deployments need their Code.gs updated and a new deployment
version published by the account owner. Installing this release does not edit
Google projects automatically. See docs/GOOGLE-SETUP.md for the full guide,
official references and the final end-to-end test.

Google quotas and network conditions still apply. This release does not
promise anonymity, undetectable traffic, maximum speed or uninterrupted service.
