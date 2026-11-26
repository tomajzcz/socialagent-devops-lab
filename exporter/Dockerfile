# syntax=docker/dockerfile:1
# Base image pinned by digest: the same bytes on every build, even if the tag moves.
FROM python:3.13-slim-trixie@sha256:7249d5587b78209a006dc4a3b5340678f84ea729239193aa559962cd8c1fce50

# Links the GHCR package to the repository.
LABEL org.opencontainers.image.source="https://github.com/tomajzcz/socialagent-devops-lab"

# No .pyc files (the root filesystem will be read-only in Kubernetes),
# unbuffered logs, no pip cache or version check in the image.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Unprivileged user with a fixed UID, so Kubernetes can enforce runAsNonRoot.
RUN groupadd --system --gid 10001 exporter \
 && useradd --system --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin exporter

WORKDIR /app

# Dependencies first: this layer is rebuilt only when requirements.txt changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

COPY main.py .

USER 10001:10001
EXPOSE 8000

# Exec form: uvicorn runs as PID 1 and gets SIGTERM directly for a clean shutdown.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
