"""SocialAgent health exporter.

Polls the public SocialAgent /api/health endpoint in the background and exposes
the last result as Prometheus metrics on /metrics. Read-only: one GET per
interval, no credentials. Prometheus can scrape /metrics as often as it likes,
the production endpoint is still called only once per interval.
"""

import asyncio
import contextlib
import logging
import os
import time
from collections.abc import AsyncIterator

import httpx
from fastapi import FastAPI, HTTPException, Response
from prometheus_client import CONTENT_TYPE_LATEST, Gauge, generate_latest

TARGET_URL = os.environ.get("TARGET_URL", "https://socialagent.cz/api/health")
PROBE_INTERVAL_SECONDS = float(os.environ.get("PROBE_INTERVAL_SECONDS", "60"))
PROBE_TIMEOUT_SECONDS = float(os.environ.get("PROBE_TIMEOUT_SECONDS", "10"))
USER_AGENT = "socialagent-lab-exporter/1.0"

# Every call runs several queries against the production database.
if PROBE_INTERVAL_SECONDS < 30:
    raise SystemExit("PROBE_INTERVAL_SECONDS must be at least 30")

STATUSES = ("ok", "degraded", "down", "unknown")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("exporter")
logging.getLogger("httpx").setLevel(logging.WARNING)  # each probe is logged below

HEALTH_STATUS = Gauge(
    "socialagent_health_status",
    "1 for the status reported by the last probe, 0 for the others",
    ["status"],
)
PROBE_SUCCESS = Gauge(
    "socialagent_health_probe_success",
    "1 if the last probe got a valid health document (any status), 0 otherwise",
)
HTTP_STATUS_CODE = Gauge(
    "socialagent_health_http_status_code",
    "HTTP status code of the last probe, 0 if there was no response",
)
PROBE_DURATION = Gauge(
    "socialagent_health_probe_duration_seconds",
    "Duration of the last probe",
)
CRON_PROBLEMS = Gauge(
    "socialagent_health_cron_problems",
    "Number of cron problems reported by the last probe, NaN if unknown",
)
LAST_PROBE = Gauge(
    "socialagent_health_last_probe_timestamp_seconds",
    "Unix time when the last probe finished",
)


async def probe(client: httpx.AsyncClient) -> None:
    """Call the health endpoint once and update all metrics."""
    status, code, cron_problems, success = "unknown", 0, float("nan"), 0
    started = time.monotonic()
    try:
        response = await client.get(TARGET_URL)
        code = response.status_code
        body = response.json()
        if isinstance(body, dict) and body.get("status") in STATUSES[:3]:
            status, success = body["status"], 1
            if isinstance(body.get("cronProblems"), int):
                cron_problems = body["cronProblems"]
    except (httpx.HTTPError, ValueError) as exc:
        log.warning("probe failed: %s: %s", type(exc).__name__, exc)
    duration = time.monotonic() - started

    for s in STATUSES:
        HEALTH_STATUS.labels(status=s).set(1 if s == status else 0)
    PROBE_SUCCESS.set(success)
    HTTP_STATUS_CODE.set(code)
    PROBE_DURATION.set(duration)
    CRON_PROBLEMS.set(cron_problems)
    LAST_PROBE.set(time.time())
    log.info("probe status=%s code=%s duration=%.2fs", status, code, duration)


async def probe_loop() -> None:
    """Probe forever, once per interval."""
    headers = {"User-Agent": USER_AGENT}
    async with httpx.AsyncClient(timeout=PROBE_TIMEOUT_SECONDS, headers=headers) as client:
        while True:
            await probe(client)
            await asyncio.sleep(PROBE_INTERVAL_SECONDS)


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    """Start the probe loop with the app and stop it on shutdown."""
    app.state.probe_task = asyncio.create_task(probe_loop())
    yield
    app.state.probe_task.cancel()
    with contextlib.suppress(asyncio.CancelledError):
        await app.state.probe_task


app = FastAPI(title="SocialAgent health exporter", lifespan=lifespan)


@app.get("/metrics")
def metrics() -> Response:
    """Prometheus scrape endpoint."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness for Kubernetes: fails if the probe loop has stopped."""
    if app.state.probe_task.done():
        raise HTTPException(status_code=503, detail="probe loop stopped")
    return {"status": "ok"}
