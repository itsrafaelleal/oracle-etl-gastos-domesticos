-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   02 - Camada de Controle e Auditoria (CTL)
-- ARQUIVO: sql/01_ddl/ctl/01_tabelas_ctl.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Criar tabelas de auditoria, lotes, etapas e catálogo de DQ.
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR CONTINUE;

-- 1. CONTROLE DE LOTES (Execução Macro)
CREATE TABLE ctl_lote (
    id_lote                 NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_ctl_lote PRIMARY KEY,
    nm_arquivo_origem       VARCHAR2(255)  NOT NULL,
    hash_arquivo_origem     RAW(32),
    dt_inicio_execucao      TIMESTAMP(6)   DEFAULT SYSTIMESTAMP NOT NULL,
    dt_fim_execucao         TIMESTAMP(6),
    ds_status               VARCHAR2(20)   DEFAULT 'RUNNING' NOT NULL,
    qt_linhas_lidas         NUMBER(10)     DEFAULT 0 NOT NULL,
    qt_linhas_validas       NUMBER(10)     DEFAULT 0 NOT NULL,
    qt_linhas_rejeitadas    NUMBER(10)     DEFAULT 0 NOT NULL,
    qt_linhas_carregadas    NUMBER(10)     DEFAULT 0 NOT NULL,
    ds_erro                 VARCHAR2(4000),
    nm_usuario_oracle       VARCHAR2(128)  DEFAULT USER NOT NULL,
    CONSTRAINT ck_ctl_lote_status 
        CHECK (ds_status IN ('RUNNING', 'SUCCESS', 'FAILED', 'PARTIAL_SUCCESS'))
);

COMMENT ON TABLE ctl_lote IS 'Rastreabilidade de cada lote de carga processado pelo pipeline.';
COMMENT ON COLUMN ctl_lote.id_lote IS 'Identificador único do lote (Surrogate Key).';
COMMENT ON COLUMN ctl_lote.nm_arquivo_origem IS 'Nome do arquivo CSV processado.';
COMMENT ON COLUMN ctl_lote.hash_arquivo_origem IS 'Hash SHA-256 da primeira linha/metadados para idempotência.';
COMMENT ON COLUMN ctl_lote.ds_status IS 'Status da execução: RUNNING, SUCCESS, FAILED ou PARTIAL_SUCCESS.';

-- 2. CONTROLE DE ETAPAS (Granularidade por Fase do ETL)
CREATE TABLE ctl_execucao_etapa (
    id_execucao_etapa       NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_ctl_execucao_etapa PRIMARY KEY,
    id_lote                 NUMBER NOT NULL,
    nm_etapa                VARCHAR2(50)   NOT NULL,
    dt_inicio               TIMESTAMP(6)   DEFAULT SYSTIMESTAMP NOT NULL,
    dt_fim                  TIMESTAMP(6),
    ds_status               VARCHAR2(20)   DEFAULT 'RUNNING' NOT NULL,
    qt_registros_processados NUMBER(10)    DEFAULT 0 NOT NULL,
    qt_registros_rejeitados  NUMBER(10)    DEFAULT 0 NOT NULL,
    ds_mensagem             VARCHAR2(4000),
    CONSTRAINT fk_ctl_etapa_lote FOREIGN KEY (id_lote)
        REFERENCES ctl_lote (id_lote) ON DELETE CASCADE,
    CONSTRAINT ck_ctl_etapa_status
        CHECK (ds_status IN ('RUNNING', 'SUCCESS', 'FAILED', 'SKIPPED'))
);

CREATE INDEX ix_ctl_etapa_lote ON ctl_execucao_etapa (id_lote);

COMMENT ON TABLE ctl_execucao_etapa IS 'Rastreia a execução e métricas de cada fase do pipeline dentro de um lote.';

-- 3. LOG DE EVENTOS E BACKTRACE (Autônomo)
CREATE TABLE ctl_log (
    id_log                  NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_ctl_log PRIMARY KEY,
    id_lote                 NUMBER,
    nm_procedimento         VARCHAR2(128)  NOT NULL,
    tp_nivel                VARCHAR2(10)   DEFAULT 'INFO' NOT NULL,
    ds_mensagem             VARCHAR2(4000) NOT NULL,
    ds_backtrace            VARCHAR2(4000),
    dt_evento               TIMESTAMP(6)   DEFAULT SYSTIMESTAMP NOT NULL,
    nm_usuario_oracle       VARCHAR2(128)  DEFAULT USER NOT NULL,
    CONSTRAINT ck_ctl_log_nivel 
        CHECK (tp_nivel IN ('DEBUG', 'INFO', 'WARN', 'ERROR', 'FATAL'))
);

CREATE INDEX ix_ctl_log_lote ON ctl_log (id_lote);
CREATE INDEX ix_ctl_log_data ON ctl_log (dt_evento);

COMMENT ON TABLE ctl_log IS 'Log detalhado de mensagens, avisos e exceções geradas por packages PL/SQL.';

-- 4. CATÁLOGO DE REGRAS DE QUALIDADE DE DADOS (DQ)
CREATE TABLE ctl_dq_regra (
    id_regra                NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_ctl_dq_regra PRIMARY KEY,
    cd_regra                VARCHAR2(30)   NOT NULL CONSTRAINT uk_ctl_dq_cd UNIQUE,
    nm_regra                VARCHAR2(100)  NOT NULL,
    ds_regra                VARCHAR2(500)  NOT NULL,
    tp_severidade           VARCHAR2(15)   DEFAULT 'BLOQUEANTE' NOT NULL,
    ds_sql_validacao        VARCHAR2(2000) NOT NULL,
    fl_ativo                CHAR(1)        DEFAULT 'S' NOT NULL,
    dt_criacao              DATE           DEFAULT SYSDATE NOT NULL,
    CONSTRAINT ck_ctl_dq_severidade
        CHECK (tp_severidade IN ('BLOQUEANTE', 'ALERTA')),
    CONSTRAINT ck_ctl_dq_ativo
        CHECK (fl_ativo IN ('S', 'N'))
);

COMMENT ON TABLE ctl_dq_regra IS 'Catálogo central de regras de qualidade de dados (Data Quality Gates).';

-- 5. HISTÓRICO DE RESULTADOS DE QUALIDADE DE DADOS (DQ)
CREATE TABLE ctl_dq_resultado (
    id_resultado            NUMBER GENERATED ALWAYS AS IDENTITY
                            CONSTRAINT pk_ctl_dq_resultado PRIMARY KEY,
    id_lote                 NUMBER NOT NULL,
    id_regra                NUMBER NOT NULL,
    dt_execucao             TIMESTAMP(6) DEFAULT SYSTIMESTAMP NOT NULL,
    ds_status               VARCHAR2(20) NOT NULL,
    qt_inconsistencias      NUMBER(10)   DEFAULT 0 NOT NULL,
    ds_detalhes             VARCHAR2(4000),
    CONSTRAINT fk_ctl_dqr_lote FOREIGN KEY (id_lote)
        REFERENCES ctl_lote (id_lote) ON DELETE CASCADE,
    CONSTRAINT fk_ctl_dqr_regra FOREIGN KEY (id_regra)
        REFERENCES ctl_dq_regra (id_regra),
    CONSTRAINT ck_ctl_dqr_status
        CHECK (ds_status IN ('APROVADO', 'REPROVADO', 'ALERTA'))
);

CREATE INDEX ix_ctl_dqr_lote ON ctl_dq_resultado (id_lote);

-- 6. PARÂMETROS GERAIS DO PIPELINE
CREATE TABLE cfg_parametro (
    cd_parametro            VARCHAR2(50)   CONSTRAINT pk_cfg_parametro PRIMARY KEY,
    vl_parametro            VARCHAR2(500)  NOT NULL,
    ds_parametro            VARCHAR2(500)  NOT NULL,
    dt_atualizacao          DATE           DEFAULT SYSDATE NOT NULL
);

COMMENT ON TABLE cfg_parametro IS 'Parâmetros de configuração e limites operacionais do pipeline.';
