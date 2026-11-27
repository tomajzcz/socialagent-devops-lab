#!/usr/bin/env bash
# Checks the alerting setup without a cluster:
#   1. promtool: syntax and unit tests of the SocialAgent alert rules
#   2. amtool: the Alertmanager config rendered from k8s/monitoring/values.yaml,
#      and which receiver gets which alert
# Runs the same way on the workstation (Docker via colima) and in CI.
# Needs docker and helm.
set -euo pipefail
cd "$(dirname "$0")/.."

# Same versions as in the cluster, pinned by digest.
PROMETHEUS_IMAGE="quay.io/prometheus/prometheus:v3.16.0@sha256:9332054523223e2ddc18d8101799d54a4a8d823b030c53216f063a6c117773cd"
ALERTMANAGER_IMAGE="quay.io/prometheus/alertmanager:v0.35.1@sha256:03d4e362b9948eee910802ddac55f9175b320862a2de1fdef5206c3213875a09"
YQ_IMAGE="mikefarah/yq:4.54.3@sha256:7834187596ad56fd5a81436114e0b0b9dd54c91bb43946d1f7145b2be5f9c3d2"
CHART_VERSION="94.1.0" # keep in sync with k8s/monitoring/README.md

# Generated files stay inside the repo, because colima shares only the home
# directory with Docker. The folder is git-ignored.
WORK=.alerting-check
rm -rf "$WORK"
mkdir -p "$WORK"

yq() { docker run --rm -i "$YQ_IMAGE" "$@"; }
promtool() { docker run --rm -v "$PWD/$WORK":/w -w /w --entrypoint promtool "$PROMETHEUS_IMAGE" "$@"; }
amtool() { docker run --rm -v "$PWD/$WORK":/w -w /w --entrypoint amtool "$ALERTMANAGER_IMAGE" "$@"; }

echo "== Alert rules"
# promtool reads plain rule files: take the rule groups out of the PrometheusRule.
yq '.spec' < k8s/exporter/prometheusrule.yaml > "$WORK/socialagent.rules.yaml"
cp k8s/exporter/tests/socialagent.rules.test.yaml "$WORK/"
promtool check rules socialagent.rules.yaml
promtool test rules socialagent.rules.test.yaml

echo "== Alertmanager config"
helm template monitoring kube-prometheus-stack \
  --repo https://prometheus-community.github.io/helm-charts --version "$CHART_VERSION" \
  --namespace monitoring --values k8s/monitoring/values.yaml \
  | yq 'select(.kind == "Secret" and .metadata.name == "alertmanager-monitoring-kube-prometheus-alertmanager") | .data["alertmanager.yaml"] | @base64d' \
  > "$WORK/alertmanager.yaml"
amtool check-config alertmanager.yaml

# Which receiver gets which alert. amtool fails if the receiver differs.
route() { amtool config routes test --config.file=alertmanager.yaml --verify.receivers="$1" "${@:2}"; }
route slack alertname=SocialAgentDown severity=critical namespace=socialagent
route slack alertname=SocialAgentDegraded severity=warning namespace=socialagent
route slack alertname=KubePodCrashLooping severity=warning namespace=kube-system
route null alertname=Watchdog severity=none
route null alertname=InfoInhibitor severity=none

echo "All alerting checks passed."
