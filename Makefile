SHELL := /bin/bash
include .env
export

.PHONY: help up down ps logs wait-healthy setup test-setup dataset test-dataset install test-all pipeline

help:
	@echo "Comandos disponíveis no projeto Oracle ETL:"
	@echo "  make up           - Inicia o container Oracle Database 23ai Free"
	@echo "  make down         - Para os containers Docker"
	@echo "  make ps           - Exibe o status e healthcheck do banco"
	@echo "  make logs         - Visualiza logs em tempo real do Oracle"
	@echo "  make wait-healthy - Aguarda o Oracle estar totalmente operacional"
	@echo "  make setup        - Cria schemas (ORC_OWNER, ORC_BI) e diretórios (SYSTEM)"
	@echo "  make dataset      - Gera 5 anos de dados sintéticos e testes de qualidade"
	@echo "  make test-dataset - Executa a suíte de validação de dados (16 asserções)"
	@echo "  make install      - Instala todo o banco (DDL, Packages, Seeds, Views)"
	@echo "  make test-all     - Executa todos os testes unitários e de integração"
	@echo "  make pipeline     - Executa o pipeline ETL para um arquivo de exemplo"

up:
	docker compose up -d

down:
	docker compose down

ps:
	docker compose ps

logs:
	docker compose logs -f oracle

wait-healthy:
	@echo "Aguardando Oracle Database inicializar (status: healthy)..."
	@until [ "$$(docker inspect -f '{{.State.Health.Status}}' orc-oracle 2>/dev/null)" = "healthy" ]; do \
		echo -n "."; \
		sleep 5; \
	done
	@echo ""
	@echo "Oracle Database pronto para conexões!"

setup:
	docker exec -i orc-oracle sqlplus -s system/${ORACLE_PASSWORD}@${ORACLE_PDB} @/opt/orc/sql/00_setup/01_setup_users_directories.sql

test-setup:
	@printf "@/opt/orc/tests/etapa_00/test_setup.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}

dataset:
	python3 tools/gerador_dados_sinteticos/gerar_dataset.py

test-dataset:
	python3 tests/etapa_01/test_dataset.py

install:
	@printf "@/opt/orc/sql/install.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}

test-all:
	@echo "=== 1. Teste Etapa 00: Setup e Privilégios ==="
	@printf "@/opt/orc/tests/etapa_00/test_setup.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 2. Teste Etapa 01: Dataset Sintético (16 asserções) ==="
	@python3 tests/etapa_01/test_dataset.py
	@echo "=== 3. Teste Etapa 02: Transação Autônoma de Logs ==="
	@printf "@/opt/orc/tests/etapa_02/test_ctl_log.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 4. Teste Etapa 03: Ingestão External Table -> RAW ==="
	@printf "@/opt/orc/tests/etapa_03/test_ingestao.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 5. Teste Etapa 04: Staging e Recomposição ==="
	@printf "@/opt/orc/tests/etapa_04/test_staging.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 6. Teste Etapa 05: Data Quality Gates ==="
	@printf "@/opt/orc/tests/etapa_05/test_dq.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 7. Teste Etapa 06: Carga DW e Idempotência ==="
	@printf "@/opt/orc/tests/etapa_06/test_dw.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 8. Teste Etapa 07: Orquestrador PKG_PIPELINE ==="
	@printf "@/opt/orc/tests/etapa_07/test_pipeline.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "=== 9. Teste Etapa 08: Views BI e Segurança RBAC ==="
	@printf "@/opt/orc/tests/etapa_08/test_views_analytics.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_bi/${ORC_BI_PASSWORD}@${ORACLE_PDB}
	@echo "=== 10. Teste Etapa 09: Performance, Benchmark e Tuning ==="
	@printf "@/opt/orc/tests/etapa_09/test_performance.sql\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
	@echo "====================================================="
	@echo "TODOS OS TESTES FORAM EXECUTADOS E APROVADOS (100% OK)!"
	@echo "====================================================="

pipeline:
	@printf "DECLARE v NUMBER; BEGIN v := pkg_pipeline.executar_carga_arquivo('orcamento_2021_01.csv'); DBMS_OUTPUT.PUT_LINE('Lote processado com sucesso: ' || v); END;\n/\nEXIT;\n" | docker exec -i orc-oracle sqlplus -s orc_owner/${ORC_OWNER_PASSWORD}@${ORACLE_PDB}
