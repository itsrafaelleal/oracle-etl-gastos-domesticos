CREATE OR REPLACE PACKAGE BODY pkg_dq AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_DQ (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    PROCEDURE executar_regras(
        p_id_lote          IN NUMBER,
        p_fl_bloqueado     OUT CHAR,
        p_qt_falhas_bloq   OUT NUMBER,
        p_qt_alertas       OUT NUMBER
    ) IS
        v_id_etapa          NUMBER;
        v_inconsistencias   NUMBER := 0;
        v_status_regra      VARCHAR2(20);
        v_detalhes          VARCHAR2(4000);
        v_erro_msg          VARCHAR2(4000);
        v_backtrace         VARCHAR2(4000);

        -- Cursor explícito justificado: percorre o catálogo de metadados de DQ
        CURSOR c_regras IS
            SELECT id_regra, cd_regra, nm_regra, tp_severidade, ds_sql_validacao
              FROM ctl_dq_regra
             WHERE fl_ativo = 'S'
             ORDER BY CASE WHEN tp_severidade = 'BLOQUEANTE' THEN 1 ELSE 2 END, id_regra;

    BEGIN
        p_fl_bloqueado := 'N';
        p_qt_falhas_bloq := 0;
        p_qt_alertas := 0;

        v_id_etapa := pkg_log.iniciar_etapa(p_id_lote, 'DATA_QUALITY_GATE');
        pkg_log.info(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', 
                     'Iniciando validação dos Quality Gates para o lote ' || p_id_lote);

        -- Limpar execuções anteriores do lote caso seja reteste
        DELETE FROM ctl_dq_resultado WHERE id_lote = p_id_lote;

        FOR r IN c_regras LOOP
            v_inconsistencias := 0;
            v_detalhes := NULL;

            BEGIN
                -- Execução de SQL dinâmico bindado ao ID do lote
                EXECUTE IMMEDIATE r.ds_sql_validacao INTO v_inconsistencias USING p_id_lote;

                IF v_inconsistencias = 0 THEN
                    v_status_regra := 'APROVADO';
                    v_detalhes := 'Validação em conformidade. Nenhuma inconsistência encontrada.';
                ELSE
                    IF r.tp_severidade = 'BLOQUEANTE' THEN
                        v_status_regra := 'REPROVADO';
                        p_qt_falhas_bloq := p_qt_falhas_bloq + 1;
                        p_fl_bloqueado := 'S';
                        v_detalhes := 'FALHA CRÍTICA: ' || v_inconsistencias || ' registro(s) violaram esta regra bloqueante.';
                        pkg_log.warn(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', 
                                     'Regra bloqueante violada [' || r.cd_regra || ']: ' || v_detalhes);
                    ELSE
                        v_status_regra := 'ALERTA';
                        p_qt_alertas := p_qt_alertas + 1;
                        v_detalhes := 'AVISO: ' || v_inconsistencias || ' registro(s) sinalizados para monitoramento.';
                        pkg_log.info(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', 
                                     'Regra de alerta [' || r.cd_regra || ']: ' || v_detalhes);
                    END IF;
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    v_status_regra := 'REPROVADO';
                    IF r.tp_severidade = 'BLOQUEANTE' THEN
                        p_qt_falhas_bloq := p_qt_falhas_bloq + 1;
                        p_fl_bloqueado := 'S';
                    END IF;
                    v_detalhes := 'Erro na execução da validação dinâmica: ' || SQLERRM;
                    pkg_log.erro(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', v_detalhes);
            END;

            -- Registrar resultado da regra
            INSERT INTO ctl_dq_resultado (
                id_lote,
                id_regra,
                dt_execucao,
                ds_status,
                qt_inconsistencias,
                ds_detalhes
            ) VALUES (
                p_id_lote,
                r.id_regra,
                SYSTIMESTAMP,
                v_status_regra,
                v_inconsistencias,
                v_detalhes
            );
        END LOOP;

        COMMIT;

        -- Avaliação consolidada do Quality Gate
        IF p_qt_falhas_bloq > 0 THEN
            pkg_log.finalizar_etapa(
                p_id_execucao_etapa      => v_id_etapa,
                p_ds_status              => pkg_log.c_status_failed,
                p_qt_registros_process   => 0,
                p_qt_registros_rejeitados => p_qt_falhas_bloq,
                p_ds_mensagem            => 'Quality Gate REPROVADO. ' || p_qt_falhas_bloq || ' regra(s) bloqueante(s) violada(s).'
            );

            RAISE_APPLICATION_ERROR(-20050, 'Quality Gate Reprovado: ' || p_qt_falhas_bloq || 
                                           ' regra(s) bloqueante(s) violada(s). Carga no DW bloqueada.');
        ELSE
            pkg_log.finalizar_etapa(
                p_id_execucao_etapa      => v_id_etapa,
                p_ds_status              => pkg_log.c_status_success,
                p_qt_registros_process   => 0,
                p_qt_registros_rejeitados => 0,
                p_ds_mensagem            => 'Quality Gate APROVADO (' || p_qt_alertas || ' alertas registrados).'
            );
            pkg_log.info(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', 
                         'Quality Gate aprovado com sucesso. Alertas: ' || p_qt_alertas);
        END IF;

    EXCEPTION
        WHEN e_quality_gate_failed THEN
            RAISE;
        WHEN OTHERS THEN
            v_erro_msg := SQLERRM;
            v_backtrace := DBMS_UTILITY.FORMAT_ERROR_BACKTRACE;
            ROLLBACK;

            IF v_id_etapa IS NOT NULL THEN
                pkg_log.finalizar_etapa(
                    p_id_execucao_etapa => v_id_etapa,
                    p_ds_status         => pkg_log.c_status_failed,
                    p_ds_mensagem       => v_erro_msg
                );
            END IF;

            pkg_log.erro(p_id_lote, 'PKG_DQ.EXECUTAR_REGRAS', v_erro_msg, v_backtrace);
            RAISE;
    END executar_regras;

    PROCEDURE executar_regras(
        p_id_lote IN NUMBER
    ) IS
        v_b CHAR(1);
        v_f NUMBER;
        v_a NUMBER;
    BEGIN
        executar_regras(p_id_lote, v_b, v_f, v_a);
    END executar_regras;

END pkg_dq;
/
