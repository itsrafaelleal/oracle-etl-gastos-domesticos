CREATE OR REPLACE PACKAGE BODY pkg_log AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_LOG (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    PROCEDURE registrar_log(
        p_id_lote         IN NUMBER DEFAULT NULL,
        p_nm_procedimento IN VARCHAR2,
        p_tp_nivel        IN VARCHAR2 DEFAULT c_nivel_info,
        p_ds_mensagem     IN VARCHAR2,
        p_ds_backtrace    IN VARCHAR2 DEFAULT NULL
    ) IS
        -- Transação autônoma: garante que o log persista mesmo se a
        -- transação chamadora sofrer ROLLBACK por erro de negócio.
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO ctl_log (
            id_lote,
            nm_procedimento,
            tp_nivel,
            ds_mensagem,
            ds_backtrace,
            dt_evento,
            nm_usuario_oracle
        ) VALUES (
            p_id_lote,
            SUBSTR(p_nm_procedimento, 1, 128),
            p_tp_nivel,
            SUBSTR(p_ds_mensagem, 1, 4000),
            SUBSTR(p_ds_backtrace, 1, 4000),
            SYSTIMESTAMP,
            USER
        );

        COMMIT;
    EXCEPTION
        WHEN OTHERS THEN
            -- Em caso de falha catastrófica no log, não interrompemos o fluxo
            -- mas garantimos que a transação autônoma seja encerrada.
            ROLLBACK;
    END registrar_log;

    PROCEDURE info(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2
    ) IS
    BEGIN
        registrar_log(p_id_lote, p_nm_procedimento, c_nivel_info, p_ds_mensagem);
    END info;

    PROCEDURE warn(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2
    ) IS
    BEGIN
        registrar_log(p_id_lote, p_nm_procedimento, c_nivel_warn, p_ds_mensagem);
    END warn;

    PROCEDURE erro(
        p_id_lote         IN NUMBER,
        p_nm_procedimento IN VARCHAR2,
        p_ds_mensagem     IN VARCHAR2,
        p_ds_backtrace    IN VARCHAR2 DEFAULT NULL
    ) IS
    BEGIN
        registrar_log(p_id_lote, p_nm_procedimento, c_nivel_error, p_ds_mensagem, p_ds_backtrace);
    END erro;

    FUNCTION iniciar_lote(
        p_nm_arquivo   IN VARCHAR2,
        p_hash_arquivo IN RAW DEFAULT NULL
    ) RETURN NUMBER IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id_lote NUMBER;
    BEGIN
        INSERT INTO ctl_lote (
            nm_arquivo_origem,
            hash_arquivo_origem,
            dt_inicio_execucao,
            ds_status,
            nm_usuario_oracle
        ) VALUES (
            p_nm_arquivo,
            p_hash_arquivo,
            SYSTIMESTAMP,
            c_status_running,
            USER
        ) RETURNING id_lote INTO v_id_lote;

        COMMIT;

        info(v_id_lote, 'PKG_LOG.INICIAR_LOTE', 'Lote de carga iniciado para o arquivo: ' || p_nm_arquivo);
        RETURN v_id_lote;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END iniciar_lote;

    PROCEDURE finalizar_lote(
        p_id_lote              IN NUMBER,
        p_ds_status            IN VARCHAR2,
        p_qt_linhas_lidas      IN NUMBER DEFAULT 0,
        p_qt_linhas_validas    IN NUMBER DEFAULT 0,
        p_qt_linhas_rejeitadas IN NUMBER DEFAULT 0,
        p_qt_linhas_carregadas IN NUMBER DEFAULT 0,
        p_ds_erro              IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        UPDATE ctl_lote
           SET dt_fim_execucao      = SYSTIMESTAMP,
               ds_status            = p_ds_status,
               qt_linhas_lidas      = p_qt_linhas_lidas,
               qt_linhas_validas    = p_qt_linhas_validas,
               qt_linhas_rejeitadas = p_qt_linhas_rejeitadas,
               qt_linhas_carregadas = p_qt_linhas_carregadas,
               ds_erro              = SUBSTR(p_ds_erro, 1, 4000)
         WHERE id_lote = p_id_lote;

        COMMIT;

        registrar_log(
            p_id_lote         => p_id_lote,
            p_nm_procedimento => 'PKG_LOG.FINALIZAR_LOTE',
            p_tp_nivel        => CASE WHEN p_ds_status = c_status_success THEN c_nivel_info ELSE c_nivel_error END,
            p_ds_mensagem     => 'Lote finalizado com status: ' || p_ds_status || 
                                 ' | Lidas: ' || p_qt_linhas_lidas || 
                                 ' | Válidas: ' || p_qt_linhas_validas || 
                                 ' | Rejeitadas: ' || p_qt_linhas_rejeitadas || 
                                 ' | Carregadas: ' || p_qt_linhas_carregadas
        );
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END finalizar_lote;

    FUNCTION iniciar_etapa(
        p_id_lote  IN NUMBER,
        p_nm_etapa IN VARCHAR2
    ) RETURN NUMBER IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id_etapa NUMBER;
    BEGIN
        INSERT INTO ctl_execucao_etapa (
            id_lote,
            nm_etapa,
            dt_inicio,
            ds_status
        ) VALUES (
            p_id_lote,
            p_nm_etapa,
            SYSTIMESTAMP,
            c_status_running
        ) RETURNING id_execucao_etapa INTO v_id_etapa;

        COMMIT;

        info(p_id_lote, 'PKG_LOG.INICIAR_ETAPA', 'Iniciando etapa: ' || p_nm_etapa);
        RETURN v_id_etapa;
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END iniciar_etapa;

    PROCEDURE finalizar_etapa(
        p_id_execucao_etapa      IN NUMBER,
        p_ds_status              IN VARCHAR2,
        p_qt_registros_process   IN NUMBER DEFAULT 0,
        p_qt_registros_rejeitados IN NUMBER DEFAULT 0,
        p_ds_mensagem            IN VARCHAR2 DEFAULT NULL
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
        v_id_lote NUMBER;
        v_nm_etapa VARCHAR2(50);
    BEGIN
        UPDATE ctl_execucao_etapa
           SET dt_fim                   = SYSTIMESTAMP,
               ds_status                = p_ds_status,
               qt_registros_processados = p_qt_registros_process,
               qt_registros_rejeitados  = p_qt_registros_rejeitados,
               ds_mensagem              = SUBSTR(p_ds_mensagem, 1, 4000)
         WHERE id_execucao_etapa = p_id_execucao_etapa
        RETURNING id_lote, nm_etapa INTO v_id_lote, v_nm_etapa;

        COMMIT;

        info(v_id_lote, 'PKG_LOG.FINALIZAR_ETAPA', 
             'Etapa ' || v_nm_etapa || ' finalizada com status: ' || p_ds_status ||
             ' (Processados: ' || p_qt_registros_process || ', Rejeitados: ' || p_qt_registros_rejeitados || ')');
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            RAISE;
    END finalizar_etapa;

END pkg_log;
/
