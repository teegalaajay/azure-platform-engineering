FROM python:3.12-slim AS builder
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

FROM python:3.12-slim
# zlib1g is fixed in Debian security (CVE-2026-76844, CVE-2026-85091) but not yet in the base image.
# Delete this RUN when the base image ships zlib1g 1:1.3.dfsg+really1.3.1-1+deb13u1 or newer (ADR-0037).
RUN apt-get update \
 && apt-get install --no-install-recommends -y zlib1g=1:1.3.dfsg+really1.3.1-1+deb13u1 \
 && rm -rf /var/lib/apt/lists/*
RUN useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY app.py .
USER 10001
CMD ["python", "app.py"]
