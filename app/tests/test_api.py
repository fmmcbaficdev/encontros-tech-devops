"""
Testes unitários — Encontros Tech API
Execução: pytest app/tests/ -v
"""

import pytest
from fastapi.testclient import TestClient

import sys
import os

# Garante que o diretório app/ está no path ao rodar de qualquer lugar
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from main import app, EVENTOS_MOCK

client = TestClient(app)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def api_client():
    """Cliente de testes reutilizável para o módulo inteiro."""
    with TestClient(app) as c:
        yield c


# ---------------------------------------------------------------------------
# Testes — Root
# ---------------------------------------------------------------------------

class TestRoot:
    def test_root_retorna_200(self, api_client):
        response = api_client.get("/")
        assert response.status_code == 200

    def test_root_contem_campos_obrigatorios(self, api_client):
        body = api_client.get("/").json()
        assert "app" in body
        assert "version" in body
        assert "docs" in body
        assert "health" in body
        assert "metrics" in body


# ---------------------------------------------------------------------------
# Testes — /health
# ---------------------------------------------------------------------------

class TestHealth:
    def test_health_retorna_200(self, api_client):
        response = api_client.get("/health")
        assert response.status_code == 200

    def test_health_status_healthy(self, api_client):
        body = api_client.get("/health").json()
        assert body["status"] == "healthy"

    def test_health_contem_timestamp(self, api_client):
        body = api_client.get("/health").json()
        assert "timestamp" in body
        assert body["timestamp"] != ""

    def test_health_contem_uptime(self, api_client):
        body = api_client.get("/health").json()
        assert "uptime_seconds" in body
        assert body["uptime_seconds"] >= 0

    def test_health_contem_version(self, api_client):
        body = api_client.get("/health").json()
        assert "version" in body

    def test_health_contem_environment(self, api_client):
        body = api_client.get("/health").json()
        assert "environment" in body

    @pytest.mark.parametrize("campo", ["status", "timestamp", "uptime_seconds", "version", "environment"])
    def test_health_campos_presentes(self, api_client, campo):
        """Verifica parametricamente que todos os campos do schema estão presentes."""
        body = api_client.get("/health").json()
        assert campo in body, f"Campo '{campo}' ausente no /health"


# ---------------------------------------------------------------------------
# Testes — /ready
# ---------------------------------------------------------------------------

class TestReady:
    def test_ready_retorna_200(self, api_client):
        response = api_client.get("/ready")
        assert response.status_code == 200

    def test_ready_campo_ready_true(self, api_client):
        body = api_client.get("/ready").json()
        assert body["ready"] is True

    def test_ready_contem_checks(self, api_client):
        body = api_client.get("/ready").json()
        assert "checks" in body
        assert isinstance(body["checks"], dict)

    def test_ready_check_api_ok(self, api_client):
        body = api_client.get("/ready").json()
        assert body["checks"].get("api") == "ok"

    def test_ready_check_mock_data_ok(self, api_client):
        body = api_client.get("/ready").json()
        assert body["checks"].get("mock_data") == "ok"

    @pytest.mark.parametrize("check", ["api", "mock_data"])
    def test_ready_checks_parametrizados(self, api_client, check):
        """Verifica parametricamente cada check de readiness."""
        body = api_client.get("/ready").json()
        assert check in body["checks"], f"Check '{check}' ausente em /ready"
        assert body["checks"][check] == "ok", f"Check '{check}' não está OK"


# ---------------------------------------------------------------------------
# Testes — /metrics
# ---------------------------------------------------------------------------

class TestMetrics:
    def test_metrics_retorna_200(self, api_client):
        response = api_client.get("/metrics")
        assert response.status_code == 200

    def test_metrics_content_type_prometheus(self, api_client):
        response = api_client.get("/metrics")
        assert "text/plain" in response.headers["content-type"]

    def test_metrics_contem_http_requests_total(self, api_client):
        response = api_client.get("/metrics")
        assert "http_requests_total" in response.text

    def test_metrics_contem_http_request_duration(self, api_client):
        response = api_client.get("/metrics")
        assert "http_request_duration_seconds" in response.text

    def test_metrics_contem_eventos_total(self, api_client):
        response = api_client.get("/metrics")
        assert "eventos_total" in response.text

    @pytest.mark.parametrize("metrica", [
        "http_requests_total",
        "http_request_duration_seconds",
        "http_requests_active",
        "eventos_total",
    ])
    def test_metrics_metricas_presentes(self, api_client, metrica):
        """Verifica parametricamente que cada métrica Prometheus está exposta."""
        response = api_client.get("/metrics")
        assert metrica in response.text, f"Métrica '{metrica}' ausente em /metrics"


# ---------------------------------------------------------------------------
# Testes — /api/v2/eventos
# ---------------------------------------------------------------------------

class TestEventos:
    def test_eventos_retorna_200(self, api_client):
        response = api_client.get("/api/v2/eventos")
        assert response.status_code == 200

    def test_eventos_schema_correto(self, api_client):
        body = api_client.get("/api/v2/eventos").json()
        assert "total" in body
        assert "page" in body
        assert "per_page" in body
        assert "data" in body

    def test_eventos_data_e_lista(self, api_client):
        body = api_client.get("/api/v2/eventos").json()
        assert isinstance(body["data"], list)

    def test_eventos_retorna_dados_mock(self, api_client):
        body = api_client.get("/api/v2/eventos").json()
        assert body["total"] == len(EVENTOS_MOCK)

    def test_eventos_paginacao_page1(self, api_client):
        body = api_client.get("/api/v2/eventos?page=1&per_page=2").json()
        assert body["page"] == 1
        assert len(body["data"]) == 2

    def test_eventos_paginacao_page2(self, api_client):
        body = api_client.get("/api/v2/eventos?page=2&per_page=2").json()
        assert body["page"] == 2
        assert len(body["data"]) == 2

    def test_eventos_filtro_por_categoria(self, api_client):
        body = api_client.get("/api/v2/eventos?categoria=DevOps").json()
        assert body["total"] >= 1
        for evento in body["data"]:
            assert evento["categoria"].lower() == "devops"

    def test_eventos_categoria_inexistente_retorna_vazio(self, api_client):
        body = api_client.get("/api/v2/eventos?categoria=CategoriaInexistente").json()
        assert body["total"] == 0
        assert body["data"] == []

    def test_evento_campos_obrigatorios(self, api_client):
        body = api_client.get("/api/v2/eventos").json()
        assert len(body["data"]) > 0
        evento = body["data"][0]
        for campo in ["id", "titulo", "descricao", "data", "local", "vagas", "categoria"]:
            assert campo in evento, f"Campo '{campo}' ausente no evento"

    @pytest.mark.parametrize("page,per_page,esperado", [
        (1, 1, 1),
        (1, 3, 3),
        (1, 10, 5),   # mock tem 5 eventos
        (2, 10, 0),   # page 2 sem dados
    ])
    def test_eventos_paginacao_parametrizada(self, api_client, page, per_page, esperado):
        """Verifica paginação com múltiplas combinações de page/per_page."""
        body = api_client.get(f"/api/v2/eventos?page={page}&per_page={per_page}").json()
        assert len(body["data"]) == esperado


# ---------------------------------------------------------------------------
# Testes — /api/v2/eventos/{id}
# ---------------------------------------------------------------------------

class TestEventoById:
    def test_evento_por_id_retorna_200(self, api_client):
        response = api_client.get("/api/v2/eventos/1")
        assert response.status_code == 200

    def test_evento_por_id_correto(self, api_client):
        body = api_client.get("/api/v2/eventos/1").json()
        assert body["id"] == 1

    def test_evento_inexistente_retorna_404(self, api_client):
        response = api_client.get("/api/v2/eventos/9999")
        assert response.status_code == 404

    def test_evento_404_contem_detail(self, api_client):
        body = api_client.get("/api/v2/eventos/9999").json()
        assert "detail" in body

    @pytest.mark.parametrize("evento_id", [1, 2, 3, 4, 5])
    def test_eventos_ids_validos(self, api_client, evento_id):
        """Verifica parametricamente que todos os IDs do mock retornam 200."""
        response = api_client.get(f"/api/v2/eventos/{evento_id}")
        assert response.status_code == 200

    @pytest.mark.parametrize("evento_id", [0, -1, 99, 1000])
    def test_eventos_ids_invalidos_retornam_404(self, api_client, evento_id):
        """Verifica parametricamente que IDs inválidos retornam 404."""
        response = api_client.get(f"/api/v2/eventos/{evento_id}")
        assert response.status_code == 404
