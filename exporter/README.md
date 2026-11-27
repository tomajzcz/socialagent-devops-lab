# SocialAgent health exporter

Prometheus exporter for the public SocialAgent health endpoint (`/api/health`).
The code lives in this folder, the Kubernetes manifests in `../k8s/exporter`.

## How it works

- A background loop calls the endpoint once per `PROBE_INTERVAL_SECONDS`
  (default 60) and keeps the last result in memory. `/metrics` only returns that
  result, so production gets one request per interval no matter how often
  Prometheus scrapes. Each call runs several queries against the production
  database, so the code refuses intervals below 30 seconds.
- Read-only: a single GET, no credentials, User-Agent `socialagent-lab-exporter/1.0`.
- `/healthz` fails when the probe loop has stopped, so the Kubernetes liveness
  probe restarts the container.

## Metrics

| Metric | Meaning |
|---|---|
| `socialagent_health_status{status}` | 1 for the status of the last probe (`ok`, `degraded`, `down`, `unknown`), 0 for the others |
| `socialagent_health_probe_success` | 1 if the endpoint returned a valid health document (any status), 0 on timeout, connection error or invalid body |
| `socialagent_health_http_status_code` | HTTP status code of the last probe, 0 without a response |
| `socialagent_health_probe_duration_seconds` | Duration of the last probe |
| `socialagent_health_cron_problems` | `cronProblems` from the endpoint, NaN when it is null |
| `socialagent_health_last_probe_timestamp_seconds` | When the last probe finished, for staleness alerts |

`status="down"` with `probe_success=1` means the app answered and reports its
database unreachable (HTTP 503). `status="unknown"` with `probe_success=0` means
the app itself could not be reached.

## Configuration

| Variable | Default |
|---|---|
| `TARGET_URL` | `https://socialagent.cz/api/health` |
| `PROBE_INTERVAL_SECONDS` | `60` (minimum 30) |
| `PROBE_TIMEOUT_SECONDS` | `10` |

## Local run

```bash
cd exporter
python3.13 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8000 --no-access-log
curl -s localhost:8000/metrics | grep '^socialagent_'
```

`requirements.in` lists the direct dependencies. `requirements.txt` is the full
pinned set: regenerate it in a fresh venv with
`pip install -r requirements.in && pip freeze > requirements.txt`.

## Image

- `python:3.13-slim-trixie` pinned by digest, runs as UID/GID 10001 and works
  with a read-only root filesystem.
- Single stage: every dependency ships as a prebuilt wheel, nothing to compile.

```bash
docker build -t socialagent-exporter:dev .
docker tag socialagent-exporter:dev "$EXPORTER_IMAGE:<version>"   # EXPORTER_IMAGE from ../.env
docker push "$EXPORTER_IMAGE:<version>"
```

Tags are never reused. The GHCR package is public, so the cluster needs no pull
secret.

## Deploy

Needs the SSH tunnel to the Kubernetes API (see `../ansible/README.md`) and the
monitoring stack from `../k8s/monitoring`, which provides the ServiceMonitor and
PrometheusRule CRDs.

```bash
kubectl kustomize ../k8s/exporter | kubeconform -strict -summary -kubernetes-version 1.37.2 -skip ServiceMonitor,PrometheusRule -
kubectl apply -k ../k8s/exporter --dry-run=server
kubectl apply -k ../k8s/exporter
kubectl -n socialagent port-forward svc/socialagent-exporter 8000:8000
```

kubeconform has no schemas for the ServiceMonitor and PrometheusRule CRDs, so
it skips them offline. The server-side dry run checks them against the CRDs in
the cluster, and the Prometheus Operator's admission webhook also checks the
PromQL in the rules.

A new version means: push a new tag, put its tag and digest into
`../k8s/exporter/deployment.yaml`, apply. The `socialagent` namespace enforces
the `restricted` Pod Security Standard.

## Monitoring

- `../k8s/exporter/servicemonitor.yaml` tells Prometheus to scrape the `http`
  port (every 30 s, the Prometheus default). Scrapes only read the last result,
  they never trigger a probe. The `release: monitoring` label is required;
  without it Prometheus ignores the ServiceMonitor without any error.
- `../k8s/exporter/dashboards/socialagent-health.json` is the Grafana dashboard
  "SocialAgent / Health". kustomize wraps it in a ConfigMap labelled
  `grafana_dashboard: "1"`, and the Grafana sidecar loads it from there.
  Grafana cannot save a provisioned dashboard: change this file and apply.
  A change made in the Grafana UI has to be copied back here as classic JSON.
- `../k8s/exporter/prometheusrule.yaml` holds the alerts below. Like the
  ServiceMonitor, it needs the `release: monitoring` label. All of them go to
  Slack, see `../k8s/monitoring/README.md`.

| Alert | Severity | Fires when |
|---|---|---|
| `SocialAgentDown` | critical | `/api/health` answers 503 `down` (database unreachable) for 2 minutes |
| `SocialAgentUnreachable` | critical | no valid answer (timeout, connection error, bad body) for 3 minutes |
| `SocialAgentDegraded` | warning | `degraded` (cron jobs stale or failing) for 15 minutes |
| `SocialAgentProbeStale` | warning | the last probe is older than 180 s for 2 minutes: the probe loop is stuck |
| `SocialAgentExporterDown` | warning | no successful scrape of the exporter for 5 minutes |

From a real outage to a Slack message takes about 3 to 5 minutes: up to 60 s
until the next probe, up to 30 s until the scrape, up to 30 s until the rule
evaluation, then the `for` duration and 30 s `group_wait` in Alertmanager.
