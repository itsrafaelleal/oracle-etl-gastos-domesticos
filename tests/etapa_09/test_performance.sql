-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   09 - Teste e Execução de Benchmark e Planos de Execução
-- ARQUIVO: tests/etapa_09/test_performance.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Executar o script de benchmark comparativo e extrair os planos
--           de execução, validando o domínio técnico de tuning.
-- =====================================================================

SET SERVEROUTPUT ON;
SET DEFINE OFF;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

PROMPT =====================================================================
PROMPT EXECUTANDO BENCHMARK DE PERFORMANCE: SET-BASED vs BULK vs LOOP
PROMPT =====================================================================
@@/opt/orc/sql/06_performance/01_benchmark_set_bulk_loop.sql

PROMPT =====================================================================
PROMPT EXTRAINDO PLANOS DE EXECUÇÃO EXPLAIN PLAN & DBMS_XPLAN
PROMPT =====================================================================
@@/opt/orc/sql/06_performance/02_explain_plans.sql

PROMPT =====================================================================
PROMPT ETAPA 09 CONCLUÍDA COM SUCESSO!
PROMPT =====================================================================
