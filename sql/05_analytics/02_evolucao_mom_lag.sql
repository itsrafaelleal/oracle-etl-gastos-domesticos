-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Consultas Analíticas Avançadas
-- ARQUIVO: sql/05_analytics/02_evolucao_mom_lag.sql
-- OBJETIVO: Evolução temporal mês a mês (Month-over-Month - MoM).
--           Demonstra Window Functions com LAG() para cálculo de variações.
-- =====================================================================

WITH gastos_mensais AS (
    SELECT 
        cal.nr_ano_mes,
        cal.ds_ano_mes,
        SUM(f.vl_movimentacao) AS vl_total_mes,
        COUNT(f.sk_movimentacao) AS qt_lancamentos
    FROM vw_bi_fato_movimentacoes f
    JOIN vw_bi_dim_calendario cal ON cal.sk_data = f.sk_data_competencia
    GROUP BY cal.nr_ano_mes, cal.ds_ano_mes
),
comparativo_mom AS (
    SELECT 
        nr_ano_mes,
        ds_ano_mes,
        vl_total_mes,
        qt_lancamentos,
        -- Valor do mês imediatamente anterior usando LAG
        LAG(vl_total_mes, 1) OVER (ORDER BY nr_ano_mes) AS vl_mes_anterior,
        -- Variação nominal em reais
        vl_total_mes - LAG(vl_total_mes, 1) OVER (ORDER BY nr_ano_mes) AS vl_variacao_nominal,
        -- Variação percentual MoM
        ROUND(
            ((vl_total_mes - LAG(vl_total_mes, 1) OVER (ORDER BY nr_ano_mes)) * 100.0) /
            NULLIF(LAG(vl_total_mes, 1) OVER (ORDER BY nr_ano_mes), 0), 2
        ) AS pct_crescimento_mom,
        -- Média móvel dos últimos 3 meses (Window Frame móvel)
        ROUND(
            AVG(vl_total_mes) OVER (
                ORDER BY nr_ano_mes
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ), 2
        ) AS media_movel_3m
    FROM gastos_mensais
)
SELECT 
    ds_ano_mes AS competencia,
    qt_lancamentos,
    TO_CHAR(vl_total_mes, 'FM999G999G990D00') AS gasto_atual,
    TO_CHAR(vl_mes_anterior, 'FM999G999G990D00') AS gasto_anterior,
    TO_CHAR(vl_variacao_nominal, 'FM999G999G990D00') AS delta_reais,
    CASE 
        WHEN pct_crescimento_mom IS NULL THEN '-'
        WHEN pct_crescimento_mom > 0 THEN '+' || pct_crescimento_mom || '%'
        ELSE pct_crescimento_mom || '%'
    END AS var_mom,
    TO_CHAR(media_movel_3m, 'FM999G999G990D00') AS media_movel_trimestre
FROM comparativo_mom
ORDER BY nr_ano_mes;
