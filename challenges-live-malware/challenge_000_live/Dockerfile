# Pinned to linux/amd64: the sample is a dynamically-linked x86-64 ELF whose
# interpreter (/lib64/ld-linux-x86-64.so.2) only exists in an amd64 rootfs.
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Tooling only. No malware bytes are baked into this image.
# The sample is curled at runtime from SAMPLE_URL (third-party host).
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        file \
        coreutils \
        iptables \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /samples/extracted /var/log

COPY start.k8s.sh /start.sh
RUN chmod +x /start.sh

WORKDIR /samples

CMD ["/start.sh"]
