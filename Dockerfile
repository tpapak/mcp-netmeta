# NetMeta MCP Server Dockerfile
# Build: docker build -t netmeta-mcp .
# Run: docker run -p 8000:8000 netmeta-mcp

FROM rocker/r-ver:4.3.2

LABEL maintainer="tosku"
LABEL description="MCP server for network meta-analysis using R netmeta package"
LABEL org.opencontainers.image.source="https://github.com/tpapak/netmeta"

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libgit2-dev \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install R dependencies step by step
# First install core packages
RUN R -e "install.packages(c('jsonlite', 'remotes'), repos='https://cloud.r-project.org/')"

# Install lme4 and xml2 which are required by meta
# lme4 has complex deps but doesn't require rgl for basic functionality
RUN R -e "install.packages(c('lme4', 'xml2'), repos='https://cloud.r-project.org/', dependencies=TRUE)"

# Install metafor and meta
RUN R -e "install.packages(c('metafor', 'meta'), repos='https://cloud.r-project.org/', dependencies=TRUE)" && \
    R -e "if (!requireNamespace('meta', quietly=TRUE)) stop('meta installation failed')"

# Install netmeta from guido-s/netmeta develop branch at pinned commit
# See NETMETA_VERSION file for version details
ARG NETMETA_COMMIT=5ecfc1d7739c3df360a694d60af0563bc43d68ea
RUN R -e "remotes::install_github('guido-s/netmeta@${NETMETA_COMMIT}', dependencies=FALSE)" && \
    R -e "if (!requireNamespace('netmeta', quietly=TRUE)) stop('netmeta installation failed')"

# Create non-root user for security
RUN useradd -m -s /bin/bash -u 1000 netmeta

# Create app directory
WORKDIR /app

# Create and activate virtual environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Upgrade pip
RUN pip install --upgrade pip

# Copy project files
COPY pyproject.toml .
COPY src/ src/
COPY README.md .

# Install Python package with HTTP dependencies
RUN pip install ".[http]"

# Change ownership to netmeta user
RUN chown -R netmeta:netmeta /app /opt/venv

# Switch to non-root user
USER netmeta

# Expose port for HTTP transport
EXPOSE 8000

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/mcp || exit 1

# Run the MCP server with HTTP transport
CMD ["python", "-m", "netmeta_mcp.http_server"]
