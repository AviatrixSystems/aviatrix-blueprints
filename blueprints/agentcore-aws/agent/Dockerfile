# Sample AgentCore Runtime container for the Aviatrix VCA PoC.
#
# Must be ARM64 (Graviton) per the AgentCore Runtime requirements. Exposes
# /ping and /invocations on :8080.
FROM --platform=linux/arm64 public.ecr.aws/docker/library/python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Install the Aviatrix DCF MITM root CA into the system trust store so that
# when the spoke gateway performs transparent TLS decryption (9.0+), the
# re-signed server certs validate without breaking boto3 / httpx / urllib.
# The PEM is fetched from the controller via scripts/fetch-avx-ca.sh.
#
# The attacker.example sink runs on Vercel with a Let's Encrypt cert, so it
# validates against the public CA chain already in this image — no custom
# CA bake-in needed for the v2 loopback path.
COPY avx-root-ca.pem /usr/local/share/ca-certificates/avx-dcf-mitm.crt
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && update-ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

# Belt-and-braces: boto3 honors AWS_CA_BUNDLE explicitly even if certifi's
# bundle is stale. Also covers edge cases where httpx-based SDKs read this.
ENV AWS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

EXPOSE 8080
CMD ["python", "app.py"]
