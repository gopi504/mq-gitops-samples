# mq-webconsole

Config-only Helm (sub)chart for the **IBM MQ web console** and the **federated
"common UI"**. It renders two ConfigMaps:

| ConfigMap | Purpose | Referenced by the QueueManager CR via |
|---|---|---|
| `<name>-mqwebuser` | console login + role mappings (`mqwebuser.xml`) | `spec.web.manualConfig.configMap.name` |
| `<name>-federation` | `setmqweb remote add` bootstrap (the common UI) | mounted into the pod at `/etc/mqm/federation` |

`<name>` = `nameOverride` (or the Helm release name if empty).

> The MQ console runs **inside the queue-manager pod**; it is not a separate
> Deployment. This chart therefore only produces configuration — your QM chart
> turns the console on (`spec.web`) and references these ConfigMaps.

---

## Use as a subchart of your queue-manager chart

### 1. Vendor it

Copy this directory into your QM chart:

```
<your-qm-chart>/
├── Chart.yaml
├── values.yaml
├── templates/
│   └── queuemanager.yaml
└── charts/
    └── mq-webconsole/        <-- this chart
```

### 2. Declare the dependency

In `<your-qm-chart>/Chart.yaml`:

```yaml
dependencies:
  - name: mq-webconsole
    version: "0.1.0"
    repository: "file://charts/mq-webconsole"
    condition: mq-webconsole.enabled
```

Then build the lock:

```bash
helm dependency build <your-qm-chart>
```

### 3. Configure it from the parent values

Subchart values live under the chart name. In `<your-qm-chart>/values.yaml`:

```yaml
mq-webconsole:
  enabled: true
  nameOverride: ""          # leave empty if QM CR name == release name
  registry: ldap
  ldap:
    host: ad.example.com
    port: 636
    sslEnabled: true
    baseDN: "dc=example,dc=com"
    bindDN: "cn=mqbind,ou=svc,dc=example,dc=com"
    bindPasswordEncoded: "{xor}REPLACE_ME"
  consoleRoles:
    admin:         [ OPS_MQ_RW ]
    adminReadOnly: [ ENG_MQ_RO ]
    user:          [ ]
  federation:
    enabled: true
    remoteQueueManagers:
      - qmgrName: QM2
        uniqueName: QM2-prod
        channel: MQ.ADMIN.SVRCONN
        connectionName: "qm2-ibm-mq.mq-prod.svc(1414)"
        username: consolesvc
```

### 4. Reference the ConfigMaps from your QueueManager CR

Add to your QueueManager template's `spec` (names use the same default as the
subchart — the release name; if you set `mq-webconsole.nameOverride`, use that
value instead of `.Release.Name`):

```yaml
  web:
    enabled: true
    console:
      authentication:
        provider: manual
      authorization:
        provider: manual
    manualConfig:
      configMap:
        name: {{ .Release.Name }}-mqwebuser
    route:
      enabled: true
  {{- if (index .Values "mq-webconsole" "federation" "enabled") }}
  template:
    pod:
      volumes:
        - name: federation
          configMap:
            name: {{ .Release.Name }}-federation
            defaultMode: 0755
      containers:
        - name: qmgr
          volumeMounts:
            - name: federation
              mountPath: /etc/mqm/federation
              readOnly: true
  {{- end }}
```

If your QM CR name is derived (not the release name), keep the ConfigMap names
aligned with this DRY helper in your parent `_helpers.tpl`:

```yaml
{{- define "myqm.consolePrefix" -}}
{{- include "mq-webconsole.fullname" (dict "Release" .Release "Values" (index .Values "mq-webconsole")) -}}
{{- end -}}
```

…then reference `{{ include "myqm.consolePrefix" . }}-mqwebuser` and
`-federation`.

### 5. Verify and install

```bash
helm template <your-qm-chart> | less        # confirm the ConfigMaps + CR refs
helm upgrade --install qm1 <your-qm-chart> -n mq-prod
```

### 6. Light up the common UI (once)

Federation is not auto-applied. On the active pod:

```bash
ACTIVE=$(oc get pods -n mq-prod -l app.kubernetes.io/instance=qm1 \
  -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' | awk '{print $1}')
REMOTE_MQ_PW=*** oc exec "$ACTIVE" -n mq-prod -- \
  bash -c 'REMOTE_MQ_PW='"$REMOTE_MQ_PW"' bash /etc/mqm/federation/federation.sh'
```

---

## Standalone use

```bash
helm template qm1 ./mq-webconsole          # just the two ConfigMaps
```

Useful to render/inspect the console config independently, or to apply it to an
existing queue manager that you then point at via `oc edit qmgr`.

---

## Migrating from the all-in-one `mq-qmgr-rbac` chart

If you were using `mq-qmgr-rbac` (which rendered these inline), to adopt this
subchart instead:

1. Delete `templates/configmap-mqwebuser.yaml` and
   `templates/configmap-federation.yaml` from `mq-qmgr-rbac` (avoid duplicate
   ConfigMaps with the same name).
2. Move the `web.registry`, `web.consoleRoles`, `web.basicUsers`, `ldap`, and
   `federation` values under a new `mq-webconsole:` block.
3. Add the dependency (step 2 above). The QueueManager CR already references
   `{{ .Release.Name }}-mqwebuser`/`-federation`, so no CR change is needed.

`clientAuth`, `tls`, `channels`, and `access` stay in the QM chart — this
subchart owns the console and the common UI only.
