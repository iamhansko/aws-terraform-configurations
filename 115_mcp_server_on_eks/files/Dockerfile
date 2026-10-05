# The MCP proxy image: mcp-proxy fronting awslabs.eks-mcp-server over streamable HTTP,
# so an IDE outside the cluster can talk to a stdio MCP server running inside it.
#
# A real file rather than a heredoc inside a CodeBuild buildspec inside a Terraform
# heredoc, which is how the _monolithic template carried it. The buildspec writes this
# file out on the build host from a value Terraform read with file(), so there is one
# copy of it and an editor can lint it.
FROM ghcr.io/sparfenyuk/mcp-proxy:latest

RUN python3 -m ensurepip --upgrade && pip install --no-cache-dir uv

ENV PATH="/root/.local/bin:/usr/local/bin:$PATH" \
    UV_PYTHON_PREFERENCE=only-system \
    UV_PYTHON_DOWNLOADS=never \
    UV_COMPILE_BYTECODE=0 \
    PYTHONUNBUFFERED=1

RUN uv tool install "awslabs.eks-mcp-server"

EXPOSE 8000

# The CMD belongs on the HEALTHCHECK's continuation line. The _monolithic template put a
# blank line between the two, so the HEALTHCHECK instruction ended with a trailing
# backslash and no command - a Dockerfile parse error - and the `CMD wget ...` that
# followed became a top-level CMD instead, which the real CMD further down then replaced.
# The image had no health check at all.
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD wget -qO- http://localhost:8000/status || exit 1

ENTRYPOINT ["catatonit", "--", "mcp-proxy"]

CMD [ \
    "--host", "0.0.0.0", \
    "--port", "8000", \
    "--pass-environment", \
    "--allow-origin", "*", \
    "--log-level", "INFO", \
    "--", \
    "uvx", "awslabs.eks-mcp-server", \
    "--allow-write", \
    "--allow-sensitive-data-access" \
]
