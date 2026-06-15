# mq-qmgr-rbac

Helm chart for creating an **IBM MQ queue manager** (IBM MQ Operator on
OpenShift) with **team-based, per-queue-manager RBAC**, plus a **web console**
and a **federated "common UI"** delivered by the bundled `mq-webconsole`
subchart. One release == one queue manager. Intended for new QM creations.

## What it sets up

- A `QueueManager` custom resource (NativeHA or SingleInstance), with mTLS PKI.
- **Client authentication**, chosen by `clientAuth`:
  - `certificate` (default) — mTLS only. `qm.ini` `SecurityPolicy=UserExternal`
    lets MQ accept cert-mapped users that exist in no directory; CONNAUTH is
    disabled; OAM authorizes the **PRINCIPAL** (the mapped MCAUSER).
  - `ldap` — LDAP CONNAUTH; OAM authorizes by **GROUP**.
- **Per-team RBAC** from the `access` matrix → generated `CHLAUTH` (cert-DN →
  MCAUSER, with issuer pinning and a deny back-stop) and `AUTHREC` (read-only /
  read-write). `access: none` = no authority + `USERSRC(NOACCESS)`.
- **Console + common UI** (`mq-webconsole` subchart): console login via LDAP or
  a basic registry, and a `setmqweb remote` bootstrap that federates other QMs
  into one pane.

The console login and the client auth are **independent subsystems**. Console
roles `MQWebAdmin`/`MQWebAdminRO` run as the server identity (no QM-side
per-user authority needed); only `MQWebUser` bridges a console user into OAM.

## Layout

```
mq-qmgr-rbac/
├── Chart.yaml                 # depends on mq-webconsole
├── values.yaml                # QM + RBAC values; nested mq-webconsole: block
├── charts/mq-webconsole/      # vendored subchart (console + federation)
├── templates/
│   ├── _helpers.tpl
│   ├── configmap-mqsc.yaml     # channels + CHLAUTH + AUTHREC (+ CONNAUTH)
│   ├── configmap-qmini.yaml    # UserExternal stanza (certificate mode)
│   ├── queuemanager.yaml
│   └── NOTES.txt
└── examples/qm3-values.yaml
```

## Prerequisites

- IBM MQ Operator installed; namespace created.
- TLS secrets: `tls.keySecret` (`tls.key` + `tls.crt`) and `tls.trustSecret`
  (`ca.crt` — the CA that signs **client** certificates).
- For LDAP console: the mqweb keystore must trust the **AD** CA (separate trust
  from the QM's). Encode console passwords: `securityUtility encode --encoding=hash '<pw>'`.

## Install

```bash
helm dependency build ./mq-qmgr-rbac        # one-time; generates Chart.lock
helm install qm1 ./mq-qmgr-rbac -n mq-prod
helm install qm3 ./mq-qmgr-rbac -n mq-prod -f examples/qm3-values.yaml
```

The subchart is vendored, so this resolves offline (air-gap friendly).

## Common UI (run once per QM)

Federation is not auto-applied. On the active pod:

```bash
ACTIVE=$(oc get pods -n mq-prod -l app.kubernetes.io/instance=qm1 \
  -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' | awk '{print $1}')
REMOTE_MQ_PW=*** oc exec "$ACTIVE" -n mq-prod -- \
  bash -c 'REMOTE_MQ_PW='"$REMOTE_MQ_PW"' bash /etc/mqm/federation/federation.sh'
```

## Key values

| Key | Purpose |
|---|---|
| `clientAuth` | `certificate` (mTLS) or `ldap` — how application clients authenticate |
| `tls.*` | QM key/trust secrets, optional `caIssuerDN` for `SSLCERTI` pinning |
| `access.platformTeams` / `access.teams` | the RBAC matrix (identity, `access`, `queuePrefix`, `sslPeer`) |
| `web.enabled` / `web.routeEnabled` | turn the console on in the QM CR |
| `mq-webconsole.registry` | console login: `ldap` or `basic` |
| `mq-webconsole.consoleRoles` | AD groups → `MQWebAdmin`/`MQWebAdminRO`/`MQWebUser` |
| `mq-webconsole.federation.remoteQueueManagers` | QMs this console federates |

## Notes

- Two trust stores to keep straight: the QM truststore (signs client certs) and
  the mqweb keystore (trusts AD CA for LDAPS). Different failures.
- Greenfield lifecycle. For an existing QM, `helm template` the subchart for the
  ConfigMaps and wire `spec.web`/`ini` via `oc edit qmgr` out of band.
- Cross-cluster federation needs the remote listener exposed via a passthrough
  Route+SNI or LoadBalancer — an HTTP Route won't carry MQ channel traffic.
