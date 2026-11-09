-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Consultas Analíticas Avançadas
-- ARQUIVO: sql/05_analytics/04_comparativo_responsaveis.sql
-- OBJETIVO: Comparativo de perfil orçamentário entre Responsáveis.
--           Demonstra agregações analíticas, proporção e ticket médio.
-- =====================================================================

WITH resumo_responsavel AS (
    SELECT 
        resp.nm_responsavel,
        c.tp_natureza,
        SUM(f.vl_movimentacao) AS vl_total,
        COUNT(f.sk_movimentacao) AS qt_transacoes,
        ROUND(AVG(f.vl_movimentacao), 2) AS ticket_medio
    FROM vw_bi_fato_movimentacoes f
    JOIN vw_bi_dim_responsavel resp ON resp.sk_responsavel = f.sk_responsavel
    JOIN vw_bi_dim_classificacao c  ON c.sk_classificacao = f.sk_classificacao
    GROUP BY resp.nm_responsavel, c.tp_natureza
)
SELECT 
    nm_responsavel,
    tp_natureza,
    qt_transacoes,
    TO_CHAR(vl_total, 'FM999G999G990D00') AS total_gasto,
    TO_CHAR(ticket_medio, 'FM999G999G990D00') AS ticket_medio,
    -- Participação percentual de cada natureza dentro do responsável
    ROUND((vl_total * 100.0) / SUM(vl_total) OVER (PARTITION BY nm_responsavel), 2) || '%' AS pct_no_responsavel,
    -- Participação percentual em relação ao orçamento doméstico total
    ROUND((vl_total * 100.0) / SUM(vl_total) OVER (), 2) || '%' AS pct_do_total_geral
FROM resumo_responsavel
ORDER BY nm_responsavel, vl_total DESC;
