CREATE OR REPLACE PACKAGE pkg_log AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_LOG (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Gerenciamento autônomo de logs, rastreabilidade de lotes
                 e métricas de execução por etapa do ETL.
       ===================================================================== */

    -- Níveis de severidade de log
    c_nivel_debug CONSTANT VARCHAR2(10) := 'DEBUG';
    c_nivel_info  CONSTANT VARCHAR2(10) := 'INFO';
    c_nivel_warn  CONSTANT VARCHAR2(10) := 'WARN';
    c_nivel_error CONSTANT VARCHAR2(10) := 'ERROR';
    c_nivel_fatal CONSTANT VARCHAR2(10) := 'FATAL';

    -- Status de Lote e Etapa
    c_status_running CONSTANT VARCHAR2(20) := 'RUNNING';
    c_status_success CONSTANT VARCHAR2(20) := 'SUCCESS';
    c_status_failed  CONSTANT VARCHAR2(20) := 'FAILED';

    /**
     * Registra uma mensagem na tabela CTL_LOG de forma autônoma.
     * Não interfere no escopo da transação que a chamou.
     */
    PROCEDURE registrar_log(
        p_id_lote         IN NUMBER DEFAULT NULL,
        p_nm_procedimento IN VARCHAR2,
        p_tp_nivel        IN VARCHAR2 DEFAULT c_nivel_info,
        p_ds_mensagem     IN VARCHAR2,
        p_ds_backtrace    IN VARCHAR2 DEFAULT NULL
    );

    /**
     * Atalhos de conveniência para registro de logs
     */
    PROCEDURE info(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2
    );

    PROCEDURE warn(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2
    );

    PROCEDURE erro(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2,
        p_ds_backtrace    IN VARCHAR2 DEFAULT NULL
    );

    /**
     * Inicia um novo lote de processamento na tabela CTL_LOTE.
     * Retorna o ID gerado via SEQUENCE/IDENTITY.
     */
    FUNCTION iniciar_lote(
        p_nm_arquivo   IN VARCHAR2,
        p_hash_arquivo IN RAW DEFAULT NULL
    ) RETURN NUMBER;

    /**
     * Finaliza o lote atualizando métricas de volumetria e status.
     */
    PROCEDURE finalizar_lote(
        p_id_lote              IN NUMBER,
        p_ds_status            IN VARCHAR2,
        p_qt_linhas_lidas      IN NUMBER DEFAULT 0,
        p_qt_linhas_validas    IN NUMBER DEFAULT 0,
        p_qt_linhas_rejeitadas IN NUMBER DEFAULT 0,
        p_qt_linhas_carregadas IN NUMBER DEFAULT 0,
        p_ds_erro              IN VARCHAR2 DEFAULT NULL
    );

    /**
     * Inicia o rastreamento de uma sub-etapa do pipeline.
     */
    FUNCTION iniciar_etapa(
        p_id_lote  IN NUMBER,
        p_nm_etapa IN VARCHAR2
    ) RETURN NUMBER;

    /**
     * Finaliza a sub-etapa registrando métricas parciais.
     */
    PROCEDURE finalizar_etapa(
        p_id_execucao_etapa      IN NUMBER,
        p_ds_status              IN VARCHAR2,
        p_qt_registros_process   IN NUMBER DEFAULT 0,
        p_qt_registros_rejeitados IN NUMBER DEFAULT 0,
        p_ds_mensagem            IN VARCHAR2 DEFAULT NULL
    );

END pkg_log;
/
