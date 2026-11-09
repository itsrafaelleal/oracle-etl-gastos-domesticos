-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   04 - Camada de Staging (Recomposição, Parse e Padronização)
-- ARQUIVO: sql/01_ddl/stg/01_stg_tabelas.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Criar tabelas STG_ORCAMENTO (dados tipados e normalizados)
--           e STG_REJEICAO (registros segregados com motivo e código).
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR CONTINUE;

-- 1. TABELA STAGING DE DADOS VÁLIDOS E PADRONIZADOS
CREATE TABLE stg_orcamento (
    id_stg              NUMBER GENERATED ALWAYS AS IDENTITY
                        CONSTRAINT pk_stg_orcamento PRIMARY KEY,
    id_lote             NUMBER NOT NULL,
    nr_linha_origem     NUMBER(10) NOT NULL,
    id_origem           NUMBER(10),
    dt_transacao        DATE NOT NULL,
    dt_competencia      DATE NOT NULL,
    nm_responsavel      VARCHAR2(100) NOT NULL,
    ds_transacao        VARCHAR2(500) NOT NULL,
    vl_transacao        NUMBER(12, 2) NOT NULL,
    nm_categoria        VARCHAR2(100) NOT NULL,
    nm_subcategoria     VARCHAR2(100) NOT NULL,
    tp_natureza         VARCHAR2(50) NOT NULL,
    ds_observacao       VARCHAR2(500),
    fl_outlier          CHAR(1) DEFAULT 'N' NOT NULL,
    fl_lag_suspeito     CHAR(1) DEFAULT 'N' NOT NULL,
    hash_negocio        RAW(32) NOT NULL,
    dt_processamento    TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_stg_lote FOREIGN KEY (id_lote)
        REFERENCES ctl_lote (id_lote) ON DELETE CASCADE,
    CONSTRAINT ck_stg_outlier CHECK (fl_outlier IN ('S', 'N')),
    CONSTRAINT ck_stg_lag CHECK (fl_lag_suspeito IN ('S', 'N'))
);

CREATE INDEX ix_stg_lote ON stg_orcamento (id_lote);
CREATE INDEX ix_stg_hash ON stg_orcamento (hash_negocio);

COMMENT ON TABLE stg_orcamento IS 'Camada de Staging: transações recompostas, tipadas, normalizadas e prontas para validação DQ e carga DW.';

-- 2. TABELA STAGING DE REJEIÇÕES (Qualidade e Rastreabilidade)
CREATE TABLE stg_rejeicao (
    id_rejeicao         NUMBER GENERATED ALWAYS AS IDENTITY
                        CONSTRAINT pk_stg_rejeicao PRIMARY KEY,
    id_lote             NUMBER NOT NULL,
    nr_linha_origem     NUMBER(10) NOT NULL,
    ds_linha_bruta      VARCHAR2(4000),
    cd_motivo_rejeicao  VARCHAR2(50) NOT NULL,
    ds_motivo_rejeicao  VARCHAR2(500) NOT NULL,
    tp_severidade       VARCHAR2(15) DEFAULT 'ERRO' NOT NULL,
    dt_rejeicao         TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_stg_rej_lote FOREIGN KEY (id_lote)
        REFERENCES ctl_lote (id_lote) ON DELETE CASCADE,
    CONSTRAINT ck_stg_rej_sev CHECK (tp_severidade IN ('ERRO', 'ALERTA'))
);

CREATE INDEX ix_stg_rej_lote ON stg_rejeicao (id_lote);

COMMENT ON TABLE stg_rejeicao IS 'Armazena registros rejeitados na staging com código do defeito, severidade e linha bruta original.';
