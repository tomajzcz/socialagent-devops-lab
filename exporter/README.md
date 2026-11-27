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
monitoring stack from `../k8s/monitoring`, which provides the ServiceMonitor CRD.

```bash
kubectl kustomize ../k8s/exporter | kubeconform -strict -summary -kubernetes-version 1.37.2 -skip ServiceMonitor -
kubectl apply -k ../k8s/exporter --dry-run=server
kubectl apply -k ../k8s/exporter
kubectl -n socialagent port-forward svc/socialagent-exporter 8000:8000
```

kubeconform has no schema for the ServiceMonitor CRD, so it skips it offline;
the server-side dry run checks it against the CRD in the cluster.

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
