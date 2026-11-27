# Alert drill

Tests the whole alerting chain (exporter, Prometheus rule, Alertmanager, Slack)
against a fake `/api/health` inside the cluster. Production is never touched;
the exporter only stops probing it for the length of the drill, about 15 minutes.

`health-mock.yaml` creates the `socialagent-test` namespace with a small Python
server that answers like SocialAgent's `route.ts`. `MOCK_STATUS` picks the
answer: `ok` (200), `degraded` (200, two cron problems) or `down` (503, the
default). It runs on the exporter image, which already has Python.

## Steps

Needs the SSH tunnel and `source .env`; run from the repository root. Keep the
Grafana dashboard, the Prometheus Alerts page and the Slack channel open.

```bash
# 1. Database outage
kubectl apply -f k8s/drill/health-mock.yaml
kubectl -n socialagent-test rollout status deploy/health-mock
kubectl -n socialagent set env deploy/socialagent-exporter \
  TARGET_URL=http://health-mock.socialagent-test:8080/api/health
kubectl diff -k k8s/exporter          # shows the drift from Git: TARGET_URL

# 2. App unreachable: the Service has no pods, connections are refused
kubectl -n socialagent-test scale deploy/health-mock --replicas=0

# 3. Back to the state in Git, then clean up
kubectl apply -k k8s/exporter
kubectl diff -k k8s/exporter          # no output: the cluster matches Git again
kubectl delete -f k8s/drill/health-mock.yaml
```

## Expected result

| Step | Grafana | Slack |
|---|---|---|
| 1 | Status `down`, HTTP 503 | `[FIRING] SocialAgentDown` after 3 to 4 minutes |
| 2 | Status `unknown`, HTTP `no response` | `[RESOLVED] SocialAgentDown`, then `[FIRING] SocialAgentUnreachable` about 3 minutes later |
| 3 | Status `ok` | `[RESOLVED] SocialAgentUnreachable` |

A resolved message can take up to 5 minutes (`group_interval`). The drill stays
in the dashboard history as a real outage, because for the exporter it was one.
To test `SocialAgentDegraded`, run
`kubectl -n socialagent-test set env deploy/health-mock MOCK_STATUS=degraded`
in step 1 instead and wait 15 minutes.
