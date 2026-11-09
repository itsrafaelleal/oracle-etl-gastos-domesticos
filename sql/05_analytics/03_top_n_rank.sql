-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Consultas Analíticas Avançadas
-- ARQUIVO: sql/05_analytics/03_top_n_rank.sql
-- OBJETIVO: Ranking dos 3 maiores lançamentos individuais de cada categoria.
--           Demonstra Window Functions com DENSE_RANK() e particionamento.
-- =====================================================================

WITH ranking_despesas AS (
    SELECT 
        c.nm_categoria,
        c.nm_subcategoria,
        c.tp_natureza,
        f.ds_descricao,
        f.vl_movimentacao,
        cal.ds_ano_mes AS competencia,
        resp.nm_responsavel,
        -- Ranking relativo por categoria
        DENSE_RANK() OVER (
            PARTITION BY c.nm_categoria 
            ORDER BY f.vl_movimentacao DESC
        ) AS rnk_categoria,
        -- Ranking global geral
        ROW_NUMBER() OVER (
            ORDER BY f.vl_movimentacao DESC
        ) AS rnk_global
    FROM vw_bi_fato_movimentacoes f
    JOIN vw_bi_dim_classificacao c  ON c.sk_classificacao = f.sk_classificacao
    JOIN vw_bi_dim_calendario cal   ON cal.sk_data = f.sk_data_competencia
    JOIN vw_bi_dim_responsavel resp ON resp.sk_responsavel = f.sk_responsavel
)
SELECT 
    nm_categoria,
    rnk_categoria AS posicao_categoria,
    rnk_global AS posicao_geral,
    ds_descricao,
    nm_subcategoria,
    tp_natureza,
    nm_responsavel,
    competencia,
    TO_CHAR(vl_movimentacao, 'FM999G999G990D00') AS valor
FROM ranking_despesas
WHERE rnk_categoria <= 3
ORDER BY nm_categoria, rnk_categoria;
