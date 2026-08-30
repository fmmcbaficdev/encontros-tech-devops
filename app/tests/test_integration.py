"""
Testes de integração — Encontros Tech API
Requer: DATABASE_URL configurado e PostgreSQL acessível.
Execução: pytest app/tests/test_integration.py -v -m integration
"""

import os
import pytest
from fastapi.testclient import TestClient

import sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from main import app

# ---------------------------------------------------------------------------
# Markers
# ---------------------------------------------------------------------------
pytestmark = pytest.mark.integration

client = TestClient(app)

DATABASE_URL = os.getenv("DATABASE_URL", "")


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def api_client():
    """Cliente de teste com ciclo de vida de módulo."""
    with TestClient(app) as c:
        yield c


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def skip_if_no_db():
    """Pula teste se DATABASE_URL não estiver configurado."""
    if not DATABASE_URL:
        pytest.skip("DATABASE_URL não configurado — pulando teste de integração")


# ---------------------------------------------------------------------------
# Testes de conectividade (não dependem de DB)
# ---------------------------------------------------------------------------

class TestIntegrationHealth:
    """Testes de saúde em ambiente integrado."""

    def test_health_em_ambiente_integrado(self, api_client):
        """Verifica health em ambiente com postgres disponível."""
        response = api_client.get("/health")
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "healthy"
        assert body["environment"] in ["development", "staging", "production", "test"]

    def test_ready_com_servicos_disponiveis(self, api_client):
        """Readiness probe deve retornar true quando serviços estão ok."""
        response = api_client.get("/ready")
        assert response.status_code == 200
        body = response.json()
        assert body["ready"] is True

    def test_metricas_acumulam_requisicoes(self, api_client):
        """Após múltiplas requisições, métricas devem acumular."""
        # Faz 5 requisições
        for _ in range(5):
            api_client.get("/health")

        metrics = api_client.get("/metrics").text
        assert "http_requests_total" in metrics
        # Confirma que o contador foi registrado
        assert 'endpoint="/health"' in metrics or "health" in metrics


# ---------------------------------------------------------------------------
# Testes de API — fluxo end-to-end
# ---------------------------------------------------------------------------

class TestIntegrationEventos:
    """Testes end-to-end de eventos."""

    def test_fluxo_listagem_e_busca(self, api_client):
        """Lista eventos e busca o primeiro por ID."""
        # Lista
        lista = api_client.get("/api/v2/eventos").json()
        assert lista["total"] > 0

        # Pega o ID do primeiro evento
        primeiro_id = lista["data"][0]["id"]

        # Busca por ID
        detalhe = api_client.get(f"/api/v2/eventos/{primeiro_id}").json()
        assert detalhe["id"] == primeiro_id

    def test_paginacao_consistente(self, api_client):
        """Paginação deve ser consistente entre páginas."""
        pg1 = api_client.get("/api/v2/eventos?page=1&per_page=2").json()
        pg2 = api_client.get("/api/v2/eventos?page=2&per_page=2").json()

        # Total deve ser o mesmo nas duas páginas
        assert pg1["total"] == pg2["total"]

        # IDs não devem se repetir entre páginas
        ids_pg1 = {e["id"] for e in pg1["data"]}
        ids_pg2 = {e["id"] for e in pg2["data"]}
        assert ids_pg1.isdisjoint(ids_pg2), "IDs repetidos entre páginas!"

    def test_filtro_categoria_end_to_end(self, api_client):
        """Filtro por categoria deve retornar apenas eventos da categoria."""
        # Descobre categorias disponíveis
        todos = api_client.get("/api/v2/eventos?per_page=100").json()
        categorias = {e["categoria"] for e in todos["data"]}

        for categoria in list(categorias)[:2]:  # testa as 2 primeiras
            resp = api_client.get(f"/api/v2/eventos?categoria={categoria}").json()
            for evento in resp["data"]:
                assert evento["categoria"].lower() == categoria.lower(), \
                    f"Evento {evento['id']} não pertence à categoria '{categoria}'"

    def test_schema_completo_de_evento(self, api_client):
        """Todos os campos obrigatórios devem estar presentes e com tipo correto."""
        lista = api_client.get("/api/v2/eventos").json()
        assert len(lista["data"]) > 0

        evento = lista["data"][0]
        assert isinstance(evento["id"], int)
        assert isinstance(evento["titulo"], str) and len(evento["titulo"]) > 0
        assert isinstance(evento["descricao"], str) and len(evento["descricao"]) > 0
        assert isinstance(evento["data"], str)
        assert isinstance(evento["local"], str)
        assert isinstance(evento["vagas"], int) and evento["vagas"] >= 0
        assert isinstance(evento["categoria"], str)

    @pytest.mark.parametrize("endpoint,expected_status", [
        ("/health", 200),
        ("/ready", 200),
        ("/metrics", 200),
        ("/api/v2/eventos", 200),
        ("/api/v2/eventos/1", 200),
        ("/api/v2/eventos/9999", 404),
        ("/rota-inexistente", 404),
    ])
    def test_status_codes_end_to_end(self, api_client, endpoint, expected_status):
        """Verifica status codes em todos os endpoints em ambiente integrado."""
        response = api_client.get(endpoint)
        assert response.status_code == expected_status, \
            f"GET {endpoint} → esperado {expected_status}, recebido {response.status_code}"


# ---------------------------------------------------------------------------
# Testes de conexão com PostgreSQL
# ---------------------------------------------------------------------------

class TestIntegrationDatabase:
    """Testes que requerem conexão com PostgreSQL."""

    def test_database_url_configurado(self):
        """Verifica se DATABASE_URL está configurado no ambiente."""
        skip_if_no_db()
        assert DATABASE_URL.startswith("postgresql://"), \
            f"DATABASE_URL inválida: {DATABASE_URL}"

    def test_conexao_database(self):
        """Testa conexão direta com o banco de dados."""
        skip_if_no_db()
        try:
            import psycopg2
            conn = psycopg2.connect(DATABASE_URL)
            cur = conn.cursor()
            cur.execute("SELECT 1")
            result = cur.fetchone()
            assert result[0] == 1
            cur.close()
            conn.close()
        except ImportError:
            pytest.skip("psycopg2 não instalado — pulando teste de conexão direta")
        except Exception as e:
            pytest.fail(f"Falha na conexão com o banco: {e}")
