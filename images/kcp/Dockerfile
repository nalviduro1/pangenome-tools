# 1KCP graph builder: environment pinned to Wang et al. 2026 Methods + the authors' workflow code.
FROM mambaorg/micromamba:2.3.3@sha256:800e7ade3ffe29c9a9ac2026163131495f8197c3852e572c5835beb4e8a33cd6
ARG KCP_REPO=https://github.com/JianYang-Lab/1KCP-analysis.git
ARG KCP_COMMIT=f428f2445bbf7a38fd4e45e162dfb552bfc4090c
USER root
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates procps patch libgomp1 \
    && rm -rf /var/lib/apt/lists/*
# *.lock: the exact packages (URL + md5) solved from environment.yml / gs.yml and tested; see README
COPY kcp.lock gs.lock /tmp/
# The optional "ca" build secret only exists for builds behind a TLS-inspecting proxy; the GitHub build does not use it.
RUN --mount=type=secret,id=ca,required=false \
    if [ -s /run/secrets/ca ]; then export MAMBA_SSL_VERIFY=/run/secrets/ca SSL_CERT_FILE=/run/secrets/ca; fi; \
    micromamba create -y -p /opt/envs/kcp -f /tmp/kcp.lock \
    && micromamba create -y -p /opt/envs/gs -f /tmp/gs.lock \
    && micromamba clean -a -y && rm -rf /opt/conda/pkgs/*
RUN --mount=type=secret,id=ca,required=false \
    if [ -s /run/secrets/ca ]; then export GIT_SSL_CAINFO=/run/secrets/ca; fi; \
    git clone "$KCP_REPO" /opt/1KCP-analysis && cd /opt/1KCP-analysis \
    && git checkout --quiet "$KCP_COMMIT" && git log -1 --format='%H %cd' > /opt/1KCP-analysis/COMMIT \
    && rm -rf .git && chmod -R a+rX /opt/1KCP-analysis
COPY kcp-init genomescope2 /opt/kcp/
COPY patches/ /opt/kcp/patches/
RUN chmod 755 /opt/kcp/kcp-init /opt/kcp/genomescope2 \
    && ln -s /opt/kcp/kcp-init /usr/local/bin/kcp-init \
    && ln -s /opt/kcp/genomescope2 /usr/local/bin/genomescope2
# CONDA_PREFIX is read by the 1KCP rule that preloads jemalloc for odgi's Python module.
ENV PATH=/opt/envs/kcp/bin:/usr/local/bin:/usr/bin:/bin \
    CONDA_PREFIX=/opt/envs/kcp \
    KCP_HOME=/opt/1KCP-analysis \
    LC_ALL=C.UTF-8 LANG=C.UTF-8

# No conda activation entrypoint: the environment is on PATH already (and apptainer exec does not run it).
ENTRYPOINT []
CMD ["/bin/bash"]
USER mambauser
