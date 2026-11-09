-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   03 - Ingestão de Dados (External Table e Camada RAW)
-- ARQUIVO: sql/01_ddl/raw/01_raw_tabelas.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Criar a External Table (EXT_ORCAMENTO) para leitura agnóstica
--           e a tabela persistente RAW_ORCAMENTO_LINHA com hash SHA-256.
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR CONTINUE;

-- 1. TABELA EXTERNA (Acesso aos arquivos CSV no Inbox sem quebrar em novas linhas)
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE ext_orcamento PURGE';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE ext_orcamento (
    nr_linha    NUMBER(10),
    ds_linha    VARCHAR2(4000)
)
ORGANIZATION EXTERNAL (
    TYPE ORACLE_LOADER
    DEFAULT DIRECTORY DIR_ORC_INBOX
    ACCESS PARAMETERS (
        RECORDS DELIMITED BY NEWLINE
        CHARACTERSET UTF8
        BADFILE DIR_ORC_LOG:'ext_orcamento_%p.bad'
        LOGFILE DIR_ORC_LOG:'ext_orcamento_%p.log'
        FIELDS (
            nr_linha RECNUM,
            ds_linha CHAR(4000)
        )
    )
    LOCATION ('orcamento_teste_defeitos.csv')
)
REJECT LIMIT UNLIMITED;

-- Observação: External tables não suportam COMMENT ON TABLE.

-- 2. TABELA PERSISTENTE RAW (Histórico Append-Only de Linhas Ingeridas)
CREATE TABLE raw_orcamento_linha (
    id_raw          NUMBER GENERATED ALWAYS AS IDENTITY
                    CONSTRAINT pk_raw_orcamento_linha PRIMARY KEY,
    id_lote         NUMBER NOT NULL,
    nm_arquivo      VARCHAR2(255) NOT NULL,
    nr_linha        NUMBER(10) NOT NULL,
    ds_linha        VARCHAR2(4000),
    hash_linha      RAW(32),
    dt_ingestao     TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_raw_lote FOREIGN KEY (id_lote)
        REFERENCES ctl_lote (id_lote) ON DELETE CASCADE
);

CREATE INDEX ix_raw_lote ON raw_orcamento_linha (id_lote);
CREATE INDEX ix_raw_arquivo ON raw_orcamento_linha (nm_arquivo);

COMMENT ON TABLE raw_orcamento_linha IS 'Armazenamento bruto (RAW) com rastreabilidade total, número da linha e hash SHA-256.';
COMMENT ON COLUMN raw_orcamento_linha.id_raw IS 'Surrogate key da linha física na camada RAW.';
COMMENT ON COLUMN raw_orcamento_linha.id_lote IS 'Identificador do lote em CTL_LOTE.';
COMMENT ON COLUMN raw_orcamento_linha.nr_linha IS 'Número da linha física no arquivo original.';
COMMENT ON COLUMN raw_orcamento_linha.ds_linha IS 'Conteúdo integral e sem transformações da linha física.';
COMMENT ON COLUMN raw_orcamento_linha.hash_linha IS 'Hash SHA-256 para auditoria e detecção de duplicidades.';
