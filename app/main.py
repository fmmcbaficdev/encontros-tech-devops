"""
Encontros Tech API v2
Aplicação FastAPI com health checks, métricas Prometheus e endpoints de negócio.
Build: CI/CD via GitHub Actions — Docker Hub push ativo.
"""

import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse
from prometheus_client import Counter, Gauge, Histogram, generate_latest, CONTENT_TYPE_LATEST
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Logging estruturado
# ---------------------------------------------------------------------------
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()

logging.basicConfig(
    level=LOG_LEVEL,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "logger": "%(name)s", "message": "%(message)s"}',
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
logger = logging.getLogger("encontros-tech")

# ---------------------------------------------------------------------------
# Variáveis de ambiente
# ---------------------------------------------------------------------------
APP_NAME: str = os.getenv("APP_NAME", "encontros-tech-api")
APP_VERSION: str = os.getenv("APP_VERSION", "2.0.0")
APP_ENV: str = os.getenv("APP_ENV", "development")
PORT: int = int(os.getenv("PORT", "8000"))

START_TIME: float = time.time()

# ---------------------------------------------------------------------------
# Métricas Prometheus
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "http_requests_total",
    "Total de requisições HTTP",
    ["method", "endpoint", "status"],
)

REQUEST_LATENCY = Histogram(
    "http_request_duration_seconds",
    "Latência das requisições HTTP em segundos",
    ["method", "endpoint"],
)

ACTIVE_REQUESTS = Gauge(
    "http_requests_active",
    "Requisições HTTP em andamento",
)

EVENTOS_TOTAL = Gauge(
    "eventos_total",
    "Total de eventos disponíveis na plataforma",
)

# ---------------------------------------------------------------------------
# Modelos Pydantic
# ---------------------------------------------------------------------------

class HealthResponse(BaseModel):
    status: str
    timestamp: str
    uptime_seconds: float
    version: str
    environment: str


class ReadyResponse(BaseModel):
    ready: bool
    checks: dict[str, str]


class Evento(BaseModel):
    id: int
    titulo: str
    descricao: str
    data: str
    local: str
    vagas: int
    categoria: str


class EventosResponse(BaseModel):
    total: int
    page: int
    per_page: int
    data: list[Evento]


# ---------------------------------------------------------------------------
# Dados mock
# ---------------------------------------------------------------------------
EVENTOS_MOCK: list[dict[str, Any]] = [
    {
        "id": 1,
        "titulo": "DevOps na Prática: CI/CD com GitHub Actions",
        "descricao": "Workshop hands-on de pipelines CI/CD do zero ao deploy em Kubernetes.",
        "data": "2025-09-15T19:00:00Z",
        "local": "Online — Zoom",
        "vagas": 200,
        "categoria": "DevOps",
    },
    {
        "id": 2,
        "titulo": "Kubernetes para Desenvolvedores",
        "descricao": "Aprenda a orquestrar containers com K8s na prática.",
        "data": "2025-09-22T19:00:00Z",
        "local": "Online — Google Meet",
        "vagas": 150,
        "categoria": "Kubernetes",
    },
    {
        "id": 3,
        "titulo": "Docker: Do Básico ao Avançado",
        "descricao": "Containerização completa com Docker e Docker Compose.",
        "data": "2025-10-01T19:00:00Z",
        "local": "Online — Zoom",
        "vagas": 300,
        "categoria": "Docker",
    },
    {
        "id": 4,
        "titulo": "Observabilidade com Prometheus e Grafana",
        "descricao": "Monitore suas aplicações com métricas, alertas e dashboards.",
        "data": "2025-10-10T19:00:00Z",
        "local": "Online — Zoom",
        "vagas": 180,
        "categoria": "Observabilidade",
    },
    {
        "id": 5,
        "titulo": "GitOps com ArgoCD",
        "descricao": "Deploy automatizado e sincronizado com Git como fonte da verdade.",
        "data": "2025-10-20T19:00:00Z",
        "local": "Online — Zoom",
        "vagas": 120,
        "categoria": "GitOps",
    },
]

# ---------------------------------------------------------------------------
# Aplicação FastAPI
# ---------------------------------------------------------------------------
app = FastAPI(
    title="Encontros Tech API",
    description="API da plataforma de eventos tech — bootcamp DevOps Pro.",
    version=APP_VERSION,
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=os.getenv("CORS_ORIGINS", "*").split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# Middleware de métricas
# ---------------------------------------------------------------------------

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """Coleta métricas de latência e contagem por endpoint."""
    ACTIVE_REQUESTS.inc()
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start

    REQUEST_COUNT.labels(
        method=request.method,
        endpoint=request.url.path,
        status=response.status_code,
    ).inc()

    REQUEST_LATENCY.labels(
        method=request.method,
        endpoint=request.url.path,
    ).observe(duration)

    ACTIVE_REQUESTS.dec()
    return response


# ---------------------------------------------------------------------------
# Endpoints de infraestrutura
# ---------------------------------------------------------------------------

@app.get(
    "/health",
    response_model=HealthResponse,
    tags=["Infraestrutura"],
    summary="Liveness probe",
)
async def health() -> HealthResponse:
    """
    Verifica se a aplicação está viva (liveness probe).
    Usado pelo Kubernetes para decidir se o pod precisa ser reiniciado.
    """
    logger.info("Health check solicitado")
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        uptime_seconds=round(time.time() - START_TIME, 2),
        version=APP_VERSION,
        environment=APP_ENV,
    )


@app.get(
    "/ready",
    response_model=ReadyResponse,
    tags=["Infraestrutura"],
    summary="Readiness probe",
)
async def ready() -> ReadyResponse:
    """
    Verifica se a aplicação está pronta para receber tráfego (readiness probe).
    Usado pelo Kubernetes para controlar o roteamento de requisições.
    """
    checks: dict[str, str] = {
        "api": "ok",
        "mock_data": "ok" if EVENTOS_MOCK else "empty",
    }

    all_ok = all(v == "ok" for v in checks.values())

    if not all_ok:
        logger.warning("Readiness check falhou: %s", checks)
        raise HTTPException(status_code=503, detail={"ready": False, "checks": checks})

    logger.info("Readiness check OK")
    return ReadyResponse(ready=True, checks=checks)


@app.get(
    "/metrics",
    tags=["Infraestrutura"],
    summary="Métricas Prometheus",
    response_class=PlainTextResponse,
)
async def metrics() -> PlainTextResponse:
    """
    Expõe métricas no formato Prometheus (scrape endpoint).
    Configure o Prometheus para coletar desta rota.
    """
    EVENTOS_TOTAL.set(len(EVENTOS_MOCK))
    return PlainTextResponse(
        content=generate_latest().decode("utf-8"),
        media_type=CONTENT_TYPE_LATEST,
    )


# ---------------------------------------------------------------------------
# Endpoints de negócio
# ---------------------------------------------------------------------------

@app.get(
    "/api/v2/eventos",
    response_model=EventosResponse,
    tags=["Eventos"],
    summary="Listar eventos",
)
async def listar_eventos(
    page: int = 1,
    per_page: int = 10,
    categoria: str | None = None,
) -> EventosResponse:
    """
    Retorna a lista paginada de eventos tech disponíveis.

    - **page**: número da página (padrão: 1)
    - **per_page**: itens por página (padrão: 10)
    - **categoria**: filtro opcional por categoria
    """
    logger.info("Listando eventos — page=%d per_page=%d categoria=%s", page, per_page, categoria)

    eventos = EVENTOS_MOCK
    if categoria:
        eventos = [e for e in eventos if e["categoria"].lower() == categoria.lower()]

    start = (page - 1) * per_page
    end = start + per_page
    paginated = eventos[start:end]

    return EventosResponse(
        total=len(eventos),
        page=page,
        per_page=per_page,
        data=[Evento(**e) for e in paginated],
    )


@app.get(
    "/api/v2/eventos/{evento_id}",
    response_model=Evento,
    tags=["Eventos"],
    summary="Buscar evento por ID",
)
async def buscar_evento(evento_id: int) -> Evento:
    """Retorna os detalhes de um evento específico pelo seu ID."""
    evento = next((e for e in EVENTOS_MOCK if e["id"] == evento_id), None)
    if not evento:
        logger.warning("Evento %d não encontrado", evento_id)
        raise HTTPException(status_code=404, detail=f"Evento {evento_id} não encontrado")
    return Evento(**evento)


# ---------------------------------------------------------------------------
# Root
# ---------------------------------------------------------------------------

@app.get("/", tags=["Root"])
async def root() -> JSONResponse:
    """Informações gerais da API."""
    return JSONResponse({
        "app": APP_NAME,
        "version": APP_VERSION,
        "environment": APP_ENV,
        "docs": "/docs",
        "health": "/health",
        "metrics": "/metrics",
    })


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    logger.info("Iniciando %s v%s em modo %s na porta %d", APP_NAME, APP_VERSION, APP_ENV, PORT)
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=PORT,
        reload=APP_ENV == "development",
        log_level=LOG_LEVEL.lower(),
    )
