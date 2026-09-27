FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/root/.local/bin:/usr/local/bin:${PATH}"

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
      curl \
      ca-certificates \
      git \
      bash \
 && rm -rf /var/lib/apt/lists/*

# Install the Cursor agent CLI. Pool workers authenticate with a
# service-account API key supplied at runtime (CURSOR_API_KEY).
RUN curl -fsS https://cursor.com/install | bash \
 && ln -sf /root/.local/bin/agent /usr/local/bin/agent \
 && ln -sf /root/.local/bin/agent /usr/local/bin/cursor-agent \
 && agent --version

WORKDIR /workspace

# Any-repo demo: empty workspace, no git remote, no clone.
# The directory is the container filesystem only (no PVC).
RUN mkdir -p /workspace && chmod 777 /workspace

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
