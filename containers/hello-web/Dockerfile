FROM python:3.12-slim AS builder
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
# zlib1g (CVE-2026-76844, CVE-2026-85091) and libzstd1 (CVE-2026-124851) are fixed in Debian security but not yet
# in the base image. Delete a pin when the base image ships that version or newer (ADR-0037):
# zlib1g 1:1.3.dfsg+really1.3.1-1+deb13u1, libzstd1 1.5.7+dfsg-1+deb13u1. Delete this RUN when both are gone.
RUN apt-get update \
 && apt-get install --no-install-recommends -y \
    zlib1g=1:1.3.dfsg+really1.3.1-1+deb13u1 \
    libzstd1=1.5.7+dfsg-1+deb13u1 \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY app.py .
USER 10001
CMD ["python", "app.py"]
