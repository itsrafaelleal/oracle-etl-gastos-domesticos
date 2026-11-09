-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   06 - Seed Dimensional e Parâmetros de Reclassificação
-- ARQUIVO: sql/03_seed/02_seed_dw.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Gerar dimensão calendário via CONNECT BY LEVEL (2020 a 2030),
--           inserir membros desconhecidos (-1) e criar tabela de reclassificação.
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR CONTINUE;

-- 1. TABELA DE CONFIGURAÇÃO DE RECLASSIFICAÇÕES MANUAIS (RN07 / T11)
CREATE TABLE cfg_regra_reclassificacao (
    id_reclassificacao      NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_cfg_reclass PRIMARY KEY,
    nm_padrao_descricao     VARCHAR2(200) NOT NULL,
    nm_categoria_nova       VARCHAR2(100) NOT NULL,
    nm_subcategoria_nova    VARCHAR2(100) NOT NULL,
    tp_natureza_nova        VARCHAR2(50)  NOT NULL,
    fl_ativo                CHAR(1)       DEFAULT 'S' NOT NULL,
    dt_cadastro             DATE          DEFAULT SYSDATE NOT NULL,
    CONSTRAINT ck_cfg_rec_atv CHECK (fl_ativo IN ('S', 'N'))
);

COMMENT ON TABLE cfg_regra_reclassificacao IS 'Regras dinâmicas e idempotentes de reclassificação orçamentária.';

-- Inserir regras iniciais de reclassificação observadas no projeto original
MERGE INTO cfg_regra_reclassificacao dest
USING (
    SELECT '%LAVAGEM%CARRO%' AS padrao, 'Transporte' AS cat, 'Manutencao_Veiculo' AS sub, 'OPEX' AS tipo FROM dual UNION ALL
    SELECT '%APOIO%BRACO%CARRO%' AS padrao, 'Transporte' AS cat, 'Manutencao_Veiculo' AS sub, 'CAPEX' AS tipo FROM dual
) src
ON (dest.nm_padrao_descricao = src.padrao)
WHEN NOT MATCHED THEN
    INSERT (nm_padrao_descricao, nm_categoria_nova, nm_subcategoria_nova, tp_natureza_nova, fl_ativo, dt_cadastro)
    VALUES (src.padrao, src.cat, src.sub, src.tipo, 'S', SYSDATE);

-- 2. MEMBROS DESCONHECIDOS (-1) NAS DIMENSÕES (Evita perda de fatos por lookup)
MERGE INTO dim_calendario dest
USING (
    SELECT 19000101 AS sk, DATE '1900-01-01' AS dt, 1900 AS ano, 1 AS mes,
           'Não Informado' AS nm_m, 'N/I' AS abrev_m, 190001 AS anomes, '01/1900' AS ds_anomes,
           1 AS tri, 'T1' AS ds_tri, 1 AS sem, 'S1' AS ds_sem,
           1 AS dia, 1 AS dsemana, 'Não Informado' AS nm_dsemana, 'N' AS fds
      FROM dual
) src
ON (dest.sk_data = src.sk)
WHEN NOT MATCHED THEN
    INSERT (sk_data, dt_data, nr_ano, nr_mes, nm_mes, nm_mes_abrev, nr_ano_mes, ds_ano_mes,
            nr_trimestre, ds_trimestre, nr_semestre, ds_semestre, nr_dia_mes, nr_dia_semana, nm_dia_semana, fl_fim_semana)
    VALUES (src.sk, src.dt, src.ano, src.mes, src.nm_m, src.abrev_m, src.anomes, src.ds_anomes,
            src.tri, src.ds_tri, src.sem, src.ds_sem, src.dia, src.dsemana, src.nm_dsemana, src.fds);

MERGE INTO dim_responsavel dest
USING (SELECT -1 AS sk, 'Não Informado' AS nm FROM dual) src
ON (dest.sk_responsavel = src.sk)
WHEN NOT MATCHED THEN
    INSERT (sk_responsavel, nm_responsavel, dt_cadastro)
    VALUES (src.sk, src.nm, SYSDATE);

MERGE INTO dim_classificacao dest
USING (SELECT -1 AS sk, 'Não Informada' AS cat, 'Não Informada' AS sub, 'OUTROS' AS tp FROM dual) src
ON (dest.sk_classificacao = src.sk)
WHEN NOT MATCHED THEN
    INSERT (sk_classificacao, nm_categoria, nm_subcategoria, tp_natureza, dt_atualizacao)
    VALUES (src.sk, src.cat, src.sub, src.tp, SYSDATE);

-- 3. GERAÇÃO DA DIMENSÃO CALENDÁRIO COMPLETA (2020 a 2030)
INSERT /*+ APPEND */ INTO dim_calendario (
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
)
SELECT 
    TO_NUMBER(TO_CHAR(d, 'YYYYMMDD')) AS sk_data,
    d AS dt_data,
    TO_NUMBER(TO_CHAR(d, 'YYYY')) AS nr_ano,
    TO_NUMBER(TO_CHAR(d, 'MM')) AS nr_mes,
    TRIM(TO_CHAR(d, 'Month', 'NLS_DATE_LANGUAGE=Portuguese')) AS nm_mes,
    TRIM(TO_CHAR(d, 'Mon', 'NLS_DATE_LANGUAGE=Portuguese')) AS nm_mes_abrev,
    TO_NUMBER(TO_CHAR(d, 'YYYYMM')) AS nr_ano_mes,
    TO_CHAR(d, 'MM/YYYY') AS ds_ano_mes,
    TO_NUMBER(TO_CHAR(d, 'Q')) AS nr_trimestre,
    'T' || TO_CHAR(d, 'Q') AS ds_trimestre,
    CASE WHEN TO_NUMBER(TO_CHAR(d, 'MM')) <= 6 THEN 1 ELSE 2 END AS nr_semestre,
    CASE WHEN TO_NUMBER(TO_CHAR(d, 'MM')) <= 6 THEN 'S1' ELSE 'S2' END AS ds_semestre,
    TO_NUMBER(TO_CHAR(d, 'DD')) AS nr_dia_mes,
    TO_NUMBER(TO_CHAR(d, 'D')) AS nr_dia_semana,
    TRIM(TO_CHAR(d, 'Day', 'NLS_DATE_LANGUAGE=Portuguese')) AS nm_dia_semana,
    CASE WHEN TO_CHAR(d, 'DY', 'NLS_DATE_LANGUAGE=English') IN ('SAT', 'SUN') THEN 'S' ELSE 'N' END AS fl_fim_semana
FROM (
    SELECT DATE '2020-01-01' + LEVEL - 1 AS d
      FROM dual
   CONNECT BY LEVEL <= (DATE '2030-12-31' - DATE '2020-01-01' + 1)
)
WHERE TO_NUMBER(TO_CHAR(d, 'YYYYMMDD')) NOT IN (SELECT sk_data FROM dim_calendario);

COMMIT;
