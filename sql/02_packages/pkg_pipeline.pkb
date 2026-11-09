CREATE OR REPLACE PACKAGE BODY pkg_pipeline AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_PIPELINE (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    PROCEDURE executar_carga_arquivo(
        p_nm_arquivo IN VARCHAR2,
        p_id_lote    OUT NUMBER
    ) IS
        v_concorrencia   NUMBER := 0;
        v_validos        NUMBER := 0;
        v_rejeitados     NUMBER := 0;
        v_carregados     NUMBER := 0;
        v_linhas_lidas   NUMBER := 0;
        v_erro_msg       VARCHAR2(4000);
        v_backtrace      VARCHAR2(4000);
    BEGIN
        -- 1. CONCORRÊNCIA E LIMPEZA DE LOTES ÓRFÃOS:
        -- Finaliza qualquer execução anterior que tenha permanecido em RUNNING por falha externa
        UPDATE ctl_lote
           SET ds_status = 'FAILED',
               dt_fim_execucao = SYSTIMESTAMP,
               ds_erro = 'Execução anterior cancelada por nova inicialização do pipeline.'
         WHERE nm_arquivo_origem = p_nm_arquivo
           AND ds_status = 'RUNNING';
        COMMIT;

        -- 2. ETAPA DE INGESTÃO (External Table -> RAW)
        p_id_lote := pkg_ingestao.carregar_arquivo(p_nm_arquivo);

        -- 3. ETAPA DE STAGING (Recomposição + Parse + Rejeições)
        pkg_staging.processar_lote(
            p_id_lote       => p_id_lote,
            p_qt_validos    => v_validos,
            p_qt_rejeitados => v_rejeitados
        );

        -- 4. ETAPA DE DATA QUALITY GATES
        -- Caso haja falha bloqueante, lança ORA-20050 e interrompe o pipeline
        pkg_dq.executar_regras(p_id_lote);

        -- 5. ETAPA DE CARGA NO DATA WAREHOUSE (Dimensões + Fato via MERGE)
        pkg_dw.carregar_dw(
            p_id_lote       => p_id_lote,
            p_qt_carregados => v_carregados
        );

        -- 6. ATUALIZAÇÃO DE ESTATÍSTICAS DO OTIMIZADOR (CBO)
        BEGIN
            DBMS_STATS.GATHER_TABLE_STATS(
                ownname          => USER,
                tabname          => 'FATO_MOVIMENTACAO',
                estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                cascade          => TRUE
            );
        EXCEPTION
            WHEN OTHERS THEN
                pkg_log.warn(p_id_lote, 'PKG_PIPELINE', 'Aviso: falha na coleta de estatísticas: ' || SQLERRM);
        END;

        -- 7. FECHAMENTO DO LOTE COM SUCESSO
        SELECT COUNT(*)
          INTO v_linhas_lidas
          FROM raw_orcamento_linha
         WHERE id_lote = p_id_lote;

        pkg_log.finalizar_lote(
            p_id_lote              => p_id_lote,
            p_ds_status            => pkg_log.c_status_success,
            p_qt_linhas_lidas      => v_linhas_lidas,
            p_qt_linhas_validas    => v_validos,
            p_qt_linhas_rejeitadas => v_rejeitados,
            p_qt_linhas_carregadas => v_carregados
        );

        pkg_log.info(p_id_lote, 'PKG_PIPELINE.EXECUTAR_CARGA_ARQUIVO', 
                     'Pipeline ETL executado com SUCESSO absoluto para o lote ' || p_id_lote);

    EXCEPTION
        WHEN pkg_dq.e_quality_gate_failed THEN
            v_erro_msg := SQLERRM;
            v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            
            IF p_id_lote IS NOT NULL THEN
                SELECT COUNT(*) INTO v_linhas_lidas FROM raw_orcamento_linha WHERE id_lote = p_id_lote;
                pkg_log.finalizar_lote(
                    p_id_lote              => p_id_lote,
                    p_ds_status            => pkg_log.c_status_failed,
                    p_qt_linhas_lidas      => v_linhas_lidas,
                    p_qt_linhas_validas    => v_validos,
                    p_qt_linhas_rejeitadas => v_rejeitados,
                    p_qt_linhas_carregadas => 0,
                    p_ds_erro              => v_erro_msg
                );
            END IF;
            pkg_log.erro(p_id_lote, 'PKG_PIPELINE', 'Pipeline abortado por Quality Gate: ' || v_erro_msg, v_backtrace);
            RAISE;

        WHEN OTHERS THEN
            v_erro_msg := SQLERRM;
            v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            ROLLBACK;

            IF p_id_lote IS NOT NULL THEN
                SELECT COUNT(*) INTO v_linhas_lidas FROM raw_orcamento_linha WHERE id_lote = p_id_lote;
                pkg_log.finalizar_lote(
                    p_id_lote              => p_id_lote,
                    p_ds_status            => pkg_log.c_status_failed,
                    p_qt_linhas_lidas      => v_linhas_lidas,
                    p_qt_linhas_validas    => v_validos,
                    p_qt_linhas_rejeitadas => v_rejeitados,
                    p_qt_linhas_carregadas => 0,
                    p_ds_erro              => v_erro_msg
                );
            END IF;
            pkg_log.erro(p_id_lote, 'PKG_PIPELINE', 'Falha catastrófica no pipeline: ' || v_erro_msg, v_backtrace);
            RAISE;
    END executar_carga_arquivo;

    FUNCTION executar_carga_arquivo(
        p_nm_arquivo IN VARCHAR2
    ) RETURN NUMBER IS
        v_id_lote NUMBER;
    BEGIN
        executar_carga_arquivo(p_nm_arquivo, v_id_lote);
        RETURN v_id_lote;
    END executar_carga_arquivo;

    PROCEDURE reprocessar_lote(
        p_id_lote IN NUMBER
    ) IS
        v_validos       NUMBER := 0;
        v_rejeitados    NUMBER := 0;
        v_carregados    NUMBER := 0;
        v_linhas_lidas  NUMBER := 0;
        v_erro_msg      VARCHAR2(4000);
        v_backtrace     VARCHAR2(4000);
    BEGIN
        pkg_log.info(p_id_lote, 'PKG_PIPELINE.REPROCESSAR_LOTE', 
                     'Iniciando reprocessamento a partir da RAW para o lote ' || p_id_lote);

        -- Verificar se o lote existe na RAW
        SELECT COUNT(*) INTO v_linhas_lidas FROM raw_orcamento_linha WHERE id_lote = p_id_lote;
        IF v_linhas_lidas = 0 THEN
            RAISE_APPLICATION_ERROR(-20061, 'Lote ' || p_id_lote || ' não encontrado na camada RAW para reprocessamento.');
        END IF;

        -- 1. Reprocessar Staging
        pkg_staging.processar_lote(p_id_lote, v_validos, v_rejeitados);

        -- 2. Reprocessar Data Quality
        pkg_dq.executar_regras(p_id_lote);

        -- 3. Reprocessar Data Warehouse
        pkg_dw.carregar_dw(p_id_lote, v_carregados);

        -- 4. Finalizar lote reprocessado
        pkg_log.finalizar_lote(
            p_id_lote              => p_id_lote,
            p_ds_status            => pkg_log.c_status_success,
            p_qt_linhas_lidas      => v_linhas_lidas,
            p_qt_linhas_validas    => v_validos,
            p_qt_linhas_rejeitadas => v_rejeitados,
            p_qt_linhas_carregadas => v_carregados
        );

        pkg_log.info(p_id_lote, 'PKG_PIPELINE.REPROCESSAR_LOTE', 
                     'Reprocessamento do lote ' || p_id_lote || ' finalizado com sucesso.');

    EXCEPTION
        WHEN OTHERS THEN
            v_erro_msg := SQLERRM;
            v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            pkg_log.erro(p_id_lote, 'PKG_PIPELINE.REPROCESSAR_LOTE', v_erro_msg, v_backtrace);
            RAISE;
    END reprocessar_lote;

END pkg_pipeline;
/
