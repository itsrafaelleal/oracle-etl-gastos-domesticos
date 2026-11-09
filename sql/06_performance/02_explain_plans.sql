-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   09 - Planos de Execução e Otimização (EXPLAIN PLAN & DBMS_XPLAN)
-- ARQUIVO: sql/06_performance/02_explain_plans.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Demonstrar o custo de execução e o plano de acesso do CBO
--           (Cost-Based Optimizer) nas consultas do Star Schema.
-- =====================================================================

SET LINESIZE 180;
SET PAGESIZE 1000;
SET FEEDBACK OFF;

-- 1. Explicar plano da junção dimensional estrela
EXPLAIN PLAN SET STATEMENT_ID = 'STARSCHEMA_JOIN' FOR
SELECT 
    cal.ds_ano_mes,
    c.nm_categoria,
    c.nm_subcategoria,
    resp.nm_responsavel,
    SUM(f.vl_movimentacao) AS total_gasto,
    COUNT(*) AS total_transacoes
FROM fato_movimentacao f
JOIN dim_calendario cal   ON cal.sk_data = f.sk_data_competencia
JOIN dim_classificacao c  ON c.sk_classificacao = f.sk_classificacao
JOIN dim_responsavel resp ON resp.sk_responsavel = f.sk_responsavel
WHERE cal.nr_ano = 2023
GROUP BY cal.ds_ano_mes, c.nm_categoria, c.nm_subcategoria, resp.nm_responsavel;

-- 2. Exibir plano formatado via DBMS_XPLAN
PROMPT =====================================================================
PROMPT PLANO DE EXECUÇÃO: CONSULTA ANALÍTICA NO MODELO STAR SCHEMA
PROMPT =====================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'STARSCHEMA_JOIN', 'TYPICAL'));

-- 3. Explicar plano do MERGE idempotente da fato
EXPLAIN PLAN SET STATEMENT_ID = 'MERGE_FATO' FOR
MERGE INTO fato_movimentacao dest
USING (
    SELECT 
        stg.id_lote,
        stg.id_origem,
        c_trans.sk_data AS sk_data_transacao,
        c_comp.sk_data  AS sk_data_competencia,
        resp.sk_responsavel,
        class.sk_classificacao,
        stg.ds_transacao AS ds_descricao,
        stg.vl_transacao AS vl_movimentacao,
        stg.fl_outlier,
        stg.fl_lag_suspeito,
        stg.ds_observacao,
        stg.hash_negocio
      FROM stg_orcamento stg
      LEFT JOIN dim_calendario c_trans ON c_trans.dt_data = stg.dt_transacao
      LEFT JOIN dim_calendario c_comp  ON c_comp.dt_data = stg.dt_competencia
      LEFT JOIN dim_responsavel resp   ON resp.nm_responsavel = stg.nm_responsavel
      LEFT JOIN dim_classificacao class ON class.nm_categoria = stg.nm_categoria AND class.nm_subcategoria = stg.nm_subcategoria
     WHERE stg.id_lote = 1
) src
ON (dest.id_origem = src.id_origem)
WHEN MATCHED THEN
    UPDATE SET dest.vl_movimentacao = src.vl_movimentacao, dest.hash_negocio = src.hash_negocio
WHEN NOT MATCHED THEN
    INSERT (id_lote, id_origem, sk_data_transacao, sk_data_competencia, sk_responsavel, sk_classificacao, ds_descricao, vl_movimentacao, fl_outlier, fl_lag_suspeito, ds_observacao, hash_negocio)
    VALUES (src.id_lote, src.id_origem, src.sk_data_transacao, src.sk_data_competencia, src.sk_responsavel, src.sk_classificacao, src.ds_descricao, src.vl_movimentacao, src.fl_outlier, src.fl_lag_suspeito, src.ds_observacao, src.hash_negocio);

PROMPT =====================================================================
PROMPT PLANO DE EXECUÇÃO: MERGE IDEMPOTENTE NA TABELA FATO
PROMPT =====================================================================
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY('PLAN_TABLE', 'MERGE_FATO', 'TYPICAL'));
