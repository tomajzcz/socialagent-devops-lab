# Monitoring: kube-prometheus-stack

Prometheus, Alertmanager and Grafana for the lab cluster, installed from the
`kube-prometheus-stack` Helm chart. Nothing is published: Prometheus and
Grafana are reached with `kubectl port-forward` through the SSH tunnel.

## What `values.yaml` changes

- **K3s components are off.** K3s runs the scheduler, controller-manager and
  kube-proxy inside the k3s process with metrics bound to localhost, and keeps
  cluster state in SQLite instead of etcd. Their targets would stay DOWN, so
  they are disabled, which also drops their alert rules and dashboards.
- **Prometheus storage.** A 10Gi volume from the K3s `local-path` provisioner
  on the node disk. local-path does not enforce the size, so `retention: 7d`
  and `retentionSize: 8GB` are the real limits. Memory limit 1536Mi, because
  the node has no swap.
- **Grafana is stateless.** No volume: the chart provisions the datasources and
  dashboards come from ConfigMaps (see `../exporter/dashboards/`). The admin
  password lives in the macOS Keychain and in a Secret created by hand, never
  in Git.

## Conventions

- The `monitoring` namespace enforces the `privileged` Pod Security level,
  because node-exporter needs the host network, PID namespace and filesystem.
  Workloads such as the exporter run in their own `restricted` namespace.
- Prometheus picks up ServiceMonitors and PrometheusRules from any namespace,
  but only with the label `release: monitoring` (the Helm release name).
  Without it nothing fails, the object is just ignored.

## Install

Needs the SSH tunnel to the Kubernetes API (see `../../ansible/README.md`).
Run from the repository root after `source .env`.

```bash
kubectl apply -f k8s/monitoring/namespace.yaml

# Grafana admin password: generate it once into the Keychain, then pipe it
# into the Secret, so it is never typed or printed.
security add-generic-password -a "$USER" -s socialagent-lab-grafana -w "$(openssl rand -base64 24)"
security find-generic-password -a "$USER" -s socialagent-lab-grafana -w | tr -d '\n' \
  | kubectl -n monitoring create secret generic grafana-admin \
      --from-literal=admin-user=admin --from-file=admin-password=/dev/stdin

helm upgrade --install monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts \
  --version 94.1.0 \
  --namespace monitoring \
  --values k8s/monitoring/values.yaml \
  --wait --timeout 10m
```

The chart NOTES mention a `monitoring-grafana` Secret. It does not exist here,
because Grafana uses `admin.existingSecret`.

On a fresh cluster install this stack before `kubectl apply -k k8s/exporter`:
the exporter's ServiceMonitor needs the CRDs that come with the chart.

## Access

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090   # http://localhost:9090
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80                   # http://localhost:3000
security find-generic-password -a "$USER" -s socialagent-lab-grafana -w | pbcopy    # password for user admin
```

Healthy state: 14 targets UP (13 from the chart, 1 for the exporter). The
`Watchdog` alert always fires by design: it is a dead man's switch that proves
the alerting pipeline works.

## Upgrading the chart

Major versions come often, mostly because of subchart updates. Before raising
`--version`:

1. Read the chart's `UPGRADE.md` in the prometheus-community/helm-charts repository.
2. Apply the new CRDs as described there. Helm installs CRDs but never upgrades them.
3. Run the install command with `--dry-run=server`, then without it.
