-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Views Semânticas para o Power BI (Camada de Apresentação)
-- ARQUIVO: sql/04_views_bi/01_views_bi.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Expor o modelo Star Schema através de views desacopladas,
--           concedendo privilégio de SELECT exclusivamente para ORC_BI.
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR CONTINUE;

-- 1. VIEW SEMÂNTICA: CALENDÁRIO
CREATE OR REPLACE VIEW vw_bi_dim_calendario AS
SELECT 
    sk_data,
    dt_data,
    nr_ano,
    nr_mes,
    nm_mes,
    nm_mes_abrev,
    nr_ano_mes,
    ds_ano_mes,
    nr_trimestre,
    ds_trimestre,
    nr_semestre,
    ds_semestre,
    nr_dia_mes,
    nr_dia_semana,
    nm_dia_semana,
    fl_fim_semana
FROM dim_calendario;

COMMENT ON TABLE vw_bi_dim_calendario IS 'Visão dimensional do calendário para consumo direto pelo Power BI.';

-- 2. VIEW SEMÂNTICA: RESPONSÁVEL
CREATE OR REPLACE VIEW vw_bi_dim_responsavel AS
SELECT 
    sk_responsavel,
    nm_responsavel,
    dt_cadastro
FROM dim_responsavel;

COMMENT ON TABLE vw_bi_dim_responsavel IS 'Visão dimensional de responsáveis para consumo pelo Power BI.';

-- 3. VIEW SEMÂNTICA: CLASSIFICAÇÃO ORÇAMENTÁRIA (Star Schema Achatado)
CREATE OR REPLACE VIEW vw_bi_dim_classificacao AS
SELECT 
    sk_classificacao,
    nm_categoria,
    nm_subcategoria,
    tp_natureza,
    dt_atualizacao
FROM dim_classificacao;

COMMENT ON TABLE vw_bi_dim_classificacao IS 'Visão dimensional de classificação (Categoria, Subcategoria, Tipo) para o Power BI.';

-- 4. VIEW SEMÂNTICA: FATO MOVIMENTAÇÕES FINANCEIRAS
CREATE OR REPLACE VIEW vw_bi_fato_movimentacoes AS
SELECT 
    sk_movimentacao,
    id_lote,
    id_origem,
    sk_data_transacao,
    sk_data_competencia,
    sk_responsavel,
    sk_classificacao,
    ds_descricao,
    vl_movimentacao,
    fl_outlier,
    fl_lag_suspeito,
    ds_observacao,
    dt_carga
FROM fato_movimentacao;

COMMENT ON TABLE vw_bi_fato_movimentacoes IS 'Visão analítica da tabela fato para conexão semântica no Power BI.';

-- 5. CONCESSÃO DE PRIVILÉGIOS (Princípio do Menor Privilégio para ORC_BI)
GRANT SELECT ON vw_bi_dim_calendario TO orc_bi;
GRANT SELECT ON vw_bi_dim_responsavel TO orc_bi;
GRANT SELECT ON vw_bi_dim_classificacao TO orc_bi;
GRANT SELECT ON vw_bi_fato_movimentacoes TO orc_bi;
