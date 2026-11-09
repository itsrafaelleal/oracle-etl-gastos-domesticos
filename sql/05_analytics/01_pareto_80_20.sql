-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Consultas Analíticas Avançadas
-- ARQUIVO: sql/05_analytics/01_pareto_80_20.sql
-- OBJETIVO: Análise de Pareto (Curva ABC / 80-20) por Subcategoria.
--           Demonstra Window Functions: SUM() OVER () e SUM() OVER (ORDER BY...)
-- =====================================================================

WITH totais_subcategoria AS (
    SELECT 
        c.nm_categoria,
        c.nm_subcategoria,
        c.tp_natureza,
        SUM(f.vl_movimentacao) AS vl_total_subcategoria,
        COUNT(f.sk_movimentacao) AS qt_transacoes
    FROM vw_bi_fato_movimentacoes f
    JOIN vw_bi_dim_classificacao c ON c.sk_classificacao = f.sk_classificacao
    GROUP BY c.nm_categoria, c.nm_subcategoria, c.tp_natureza
),
calculo_pareto AS (
    SELECT 
        nm_categoria,
        nm_subcategoria,
        tp_natureza,
        vl_total_subcategoria,
        qt_transacoes,
        -- Soma total de todos os gastos (Window Function de partição global)
        SUM(vl_total_subcategoria) OVER () AS vl_total_geral,
        -- Soma acumulada ordenada decrescente por valor
        SUM(vl_total_subcategoria) OVER (
            ORDER BY vl_total_subcategoria DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS vl_acumulado,
        -- Percentual individual da subcategoria
        ROUND((vl_total_subcategoria * 100.0) / SUM(vl_total_subcategoria) OVER (), 2) AS pct_individual,
        -- Percentual acumulado da Curva de Pareto
        ROUND((SUM(vl_total_subcategoria) OVER (
            ORDER BY vl_total_subcategoria DESC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) * 100.0) / SUM(vl_total_subcategoria) OVER (), 2) AS pct_acumulado
    FROM totais_subcategoria
)
SELECT 
    nm_categoria,
    nm_subcategoria,
    tp_natureza,
    qt_transacoes,
    TO_CHAR(vl_total_subcategoria, 'FM999G999G990D00') AS total_gasto,
    pct_individual || '%' AS pct_individual,
    TO_CHAR(vl_acumulado, 'FM999G999G990D00') AS total_acumulado,
    pct_acumulado || '%' AS pct_acumulado,
    CASE 
        WHEN pct_acumulado <= 80 THEN 'Classe A (80% dos Gastos)'
        WHEN pct_acumulado <= 95 THEN 'Classe B (15% Seguintes)'
        ELSE 'Classe C (5% Restantes)'
    END AS classificacao_pareto
FROM calculo_pareto
ORDER BY vl_total_subcategoria DESC;
