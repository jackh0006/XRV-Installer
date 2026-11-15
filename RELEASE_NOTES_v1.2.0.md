# XRV v1.2.0 — safer, smarter port setup

XRV now makes port selection easier without exposing extra services.

## Port-aware setup

- The server installer checks both TCP and UDP listeners before it starts.
- If a TCP port is occupied, it reports the owning process and offers free,
  common HTTPS-style alternatives.
- You can choose both ports independently:

  ```bash
  sudo bash xrv-install.sh --server --non-interactive --yes \
    --domain vpn.example.com --email you@example.com \
    --public-port 10443 --backend-port 19443
  ```

- The public port is opened by supported firewall managers. The backend stays
  loopback-only and is never opened to the internet.

## Reliability and safety

- A collision is detected before the relay is restarted, with an actionable
  error instead of a generic service failure.
- The installer now downloads its companion client script from the repository
  default `main` branch.

## Upgrade

Existing installs keep their current ports. Re-run the server installer to
change them; point clients at the new public port afterwards.
