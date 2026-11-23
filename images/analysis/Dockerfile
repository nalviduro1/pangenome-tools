# Pangenome analysis tools not provided by the Cactus image.
FROM mambaorg/micromamba:2.3.3@sha256:800e7ade3ffe29c9a9ac2026163131495f8197c3852e572c5835beb4e8a33cd6
USER root
RUN apt-get update && apt-get install -y --no-install-recommends procps ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# analysis.lock: the exact packages (URL + md5) solved from environment.yml and tested; see README
COPY analysis.lock /tmp/
# The optional "ca" build secret only exists for builds behind a TLS-inspecting proxy; the GitHub build does not use it.
RUN --mount=type=secret,id=ca,required=false \
    if [ -s /run/secrets/ca ]; then export MAMBA_SSL_VERIFY=/run/secrets/ca SSL_CERT_FILE=/run/secrets/ca; fi; \
    micromamba create -y -p /opt/envs/analysis -f /tmp/analysis.lock \
    && micromamba clean -a -y && rm -rf /opt/conda/pkgs/*
# pangene.js (the 'call' and 'gfa2matrix' companion script of pangene 1.1-r231) is not in the conda package.
RUN --mount=type=secret,id=ca,required=false \
    if [ -s /run/secrets/ca ]; then export SSL_CERT_FILE=/run/secrets/ca; fi; \
    /opt/envs/analysis/bin/python3 -c "import urllib.request,ssl,os; ctx=ssl.create_default_context(cafile=os.environ.get('SSL_CERT_FILE')); open('/opt/envs/analysis/bin/pangene.js','wb').write(urllib.request.urlopen('https://raw.githubusercontent.com/lh3/pangene/v1.1/pangene.js', context=ctx).read())" \
    && echo "ed2fab7e8054abd874f333f95e140a15081d79b1d02b8b51aec927f394086571  /opt/envs/analysis/bin/pangene.js" | sha256sum -c - \
    && chmod 755 /opt/envs/analysis/bin/pangene.js
ENV PATH=/opt/envs/analysis/bin:/usr/local/bin:/usr/bin:/bin \
    CONDA_PREFIX=/opt/envs/analysis \
    LC_ALL=C.UTF-8 LANG=C.UTF-8

# No conda activation entrypoint: the environment is on PATH already (and apptainer exec does not run it).
ENTRYPOINT []
CMD ["/bin/bash"]
USER mambauser
