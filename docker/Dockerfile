# =============================================================================
# Encontros Tech API — Dockerfile Multi-Stage
# Stage 1: builder  → instala dependências e compila wheels
# Stage 2: runtime  → imagem mínima de produção (< 300 MB)
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: builder
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Metadados
LABEL stage="builder"

# Variáveis de build
ARG PIP_NO_CACHE_DIR=1
ARG PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Instalar dependências de sistema necessárias apenas para compilar wheels
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        gcc \
    && rm -rf /var/lib/apt/lists/*

# Copiar e instalar dependências Python como wheels no diretório /wheels
COPY app/requirements.txt .

RUN pip install --upgrade pip \
    && pip wheel \
        --no-cache-dir \
        --wheel-dir /wheels \
        -r requirements.txt


# -----------------------------------------------------------------------------
# Stage 2: runtime
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS runtime

# Metadados da imagem
LABEL maintainer="DevOps Engineer <devops@encontros-tech.com>" \
      org.opencontainers.image.title="Encontros Tech API" \
      org.opencontainers.image.description="API FastAPI da plataforma de eventos tech" \
      org.opencontainers.image.version="2.0.0" \
      org.opencontainers.image.source="https://github.com/fmmcbaficdev/encontros-tech-devops"

# -----------------------------------------------------------------------------
# Variáveis de ambiente
# -----------------------------------------------------------------------------
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONFAULTHANDLER=1 \
    APP_NAME=encontros-tech-api \
    APP_VERSION=2.0.0 \
    APP_ENV=production \
    PORT=8000 \
    WORKERS=2 \
    LOG_LEVEL=info \
    CORS_ORIGINS=*

# -----------------------------------------------------------------------------
# Dependências mínimas de runtime (apenas curl para health check)
# -----------------------------------------------------------------------------
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# -----------------------------------------------------------------------------
# Usuário não-root (segurança)
# -----------------------------------------------------------------------------
RUN groupadd --gid 1000 appgroup \
    && useradd --uid 1000 --gid appgroup --no-create-home --shell /bin/false appuser

# -----------------------------------------------------------------------------
# Instalar wheels compilados no stage builder
# -----------------------------------------------------------------------------
COPY --from=builder /wheels /wheels

RUN pip install --no-cache-dir --no-index --find-links=/wheels /wheels/* \
    && rm -rf /wheels \
    && pip uninstall -y pip setuptools wheel 2>/dev/null || true \
    && find /usr/local/lib/python3.11 -name "*.pyc" -delete \
    && find /usr/local/lib/python3.11 -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

# -----------------------------------------------------------------------------
# Código da aplicação
# -----------------------------------------------------------------------------
WORKDIR /app

COPY --chown=appuser:appgroup app/main.py .

# Garantir permissões corretas
RUN chmod 555 /app/main.py

# Mudar para usuário não-root
USER appuser

# -----------------------------------------------------------------------------
# Porta exposta
# -----------------------------------------------------------------------------
EXPOSE ${PORT}

# -----------------------------------------------------------------------------
# Health check (liveness probe nativa do Docker)
# -----------------------------------------------------------------------------
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=15s \
            --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

# -----------------------------------------------------------------------------
# Entrypoint
# -----------------------------------------------------------------------------
CMD ["sh", "-c", \
     "uvicorn main:app \
        --host 0.0.0.0 \
        --port ${PORT} \
        --workers ${WORKERS} \
        --log-level ${LOG_LEVEL} \
        --no-access-log"]
