# Google setup and connection verification

The VPS installer generates the script with your chosen public port and prints
the deployment instructions. Read either file again on the VPS:

```bash
sudo cat /etc/xrv/Code.gs
sudo cat /etc/xrv/GOOGLE-SETUP.txt
```

With the current installer you can also run:

```bash
sudo bash xrv-install.sh --google-guide
```

## Deploy the script

1. Open [Apps Script](https://script.google.com) and create a new project.
2. Replace all sample code in Code.gs with the generated file. Check that
   RELAY_URLS contains your VPS HTTPS URL, chosen public port and /tunnel.
   Never paste the tunnel key into the script or Google Script Properties.
3. Save. Choose Deploy → New deployment → gear icon → Web app.
4. Set Execute as to Me and access to Anyone (anonymous access). Authorize your
   own reviewed project for external requests. No Gmail, Drive or Contacts
   permissions are required by this forwarder. Organization policies can block
   anonymous deployment; consult the administrator if the option is absent.
5. Copy the deployed /exec URL or its AKfycb... deployment ID. Neither the
   editor's project ID nor the /dev test URL is suitable for client setup.

These settings follow Google's [web app deployment model](https://developers.google.com/apps-script/guides/web).
When updating an existing script, use Manage deployments → Edit → New version →
Deploy. Saving the editor alone does not publish your edits.

## Check Google, then check actual traffic

Open the /exec URL in a signed-out browser. Expect JSON containing ok:true,
version and protocol. A login page means anonymous access is not configured.
Alternatively, replace DEPLOYMENT_ID below:

```bash
curl -fSL 'https://script.google.com/macros/s/DEPLOYMENT_ID/exec'
```

The -L follows Google's normal
[ContentService redirect](https://developers.google.com/apps-script/guides/content).
This only proves the web app runs; it does not prove that the VPS or encrypted
tunnel works.

On the client device, download and run xrv-client.sh as described in the
[Quick Start](QUICK-START.md). Pass your complete relay URL with --relay to keep
its exact scheme and port. Supply the deployment ID and paste the key privately
from `sudo cat /etc/xrv/tunnel_key` on the VPS.

Start the client, then test:

```bash
~/xrv/start-xrv.sh
curl --socks5-hostname 127.0.0.1:1080 https://api.ipify.org
```

Expect the VPS exit IP, or your configured upstream proxy's exit IP. Configure
your browser/app to use SOCKS5 127.0.0.1:1080 with proxy DNS. On Android, exclude
Termux from any app that routes device traffic through this proxy to avoid a
routing loop.

## What the script protects

The forwarder preserves the existing encrypted-payload protocol. It has no
tunnel key and never selects its upstream URL from request input. HTTPS
certificate validation is enabled, upstream redirects are disabled, and errors
omit upstream response bodies and raw exception text. Invocation counting is
off by default, avoiding unnecessary storage calls. It uses supported
[UrlFetchApp options](https://developers.google.com/apps-script/reference/url-fetch/url-fetch-app);
there is no documented per-request deadline option.

Google still knows the hosting account, relay address and traffic metadata.
The VPS is the tunnel exit; destination HTTPS remains necessary. This is not
an anonymity guarantee, traffic camouflage guarantee, or a guarantee against
blocking. Google can record execution metadata even without application logs.
Anonymous web apps can consume account quota when invoked by others. Keep
deployment links private, but do not treat them as authentication credentials.

## Reliability and troubleshooting

Start with the client defaults. Measure latency and throughput before increasing
parallel sessions; more concurrency can reduce reliability. Google's
[quotas](https://developers.google.com/apps-script/guides/services/quotas) limit
fetch calls, executions, runtime and response sizes and can change. Multiple
deployments under one account do not create independent per-user quota.
No configuration guarantees maximum speed or uninterrupted service.

For fetch errors, check the VPS's public port, DNS, certificate chain and
firewall with `sudo bash xrv-install.sh --check`. For client failures run
`bash xrv-client.sh --check`. Quota errors require reduced load and quota
recovery. Do not disable TLS checks or blindly retry POST requests: a failed
response does not prove the upstream did not process a request.

Publishing requires your Google account authorization. Local automated tests
exercise the generated script with mocked Google services; final deployment
and the SOCKS traffic test above must succeed in your own account and network.
