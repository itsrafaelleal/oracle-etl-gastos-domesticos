CREATE OR REPLACE PACKAGE BODY pkg_dw AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_DW (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    PROCEDURE carregar_dw(
        p_id_lote        IN NUMBER,
        p_qt_carregados  OUT NUMBER
    ) IS
        v_id_etapa      NUMBER;
        v_qt_rec        NUMBER := 0;
        v_qt_resp       NUMBER := 0;
        v_qt_class      NUMBER := 0;
        v_qt_fato       NUMBER := 0;
        v_erro_msg      VARCHAR2(4000);
        v_backtrace     VARCHAR2(4000);
    BEGIN
        v_id_etapa := pkg_log.iniciar_etapa(p_id_lote, 'CARGA_DW');
        pkg_log.info(p_id_lote, 'PKG_DW.CARREGAR_DW', 
                     'Iniciando carga dimensional do Data Warehouse para o lote ' || p_id_lote);

        -- 1. APLICAR RECLASSIFICAÇÕES AUTOMÁTICAS (RN07 / T11)
        MERGE INTO stg_orcamento stg
        USING (
            SELECT stg2.rowid AS rid, r.nm_categoria_nova, r.nm_subcategoria_nova, r.tp_natureza_nova
              FROM stg_orcamento stg2
              JOIN cfg_regra_reclassificacao r
                ON UPPER(stg2.ds_transacao) LIKE UPPER(r.nm_padrao_descricao)
             WHERE stg2.id_lote = p_id_lote
               AND r.fl_ativo = 'S'
        ) rec
        ON (stg.rowid = rec.rid)
        WHEN MATCHED THEN
            UPDATE SET stg.nm_categoria    = rec.nm_categoria_nova,
                       stg.nm_subcategoria = rec.nm_subcategoria_nova,
                       stg.tp_natureza     = rec.tp_natureza_nova;

        v_qt_rec := SQL%ROWCOUNT;
        IF v_qt_rec > 0 THEN
            pkg_log.info(p_id_lote, 'PKG_DW.CARREGAR_DW', 
                         'Reclassificações de negócio aplicadas: ' || v_qt_rec || ' transações atualizadas.');
        END IF;

        -- 2. MERGE EM DIM_RESPONSAVEL
        MERGE INTO dim_responsavel dest
        USING (
            SELECT DISTINCT nm_responsavel
              FROM stg_orcamento
             WHERE id_lote = p_id_lote
               AND nm_responsavel IS NOT NULL
        ) src
        ON (dest.nm_responsavel = src.nm_responsavel)
        WHEN NOT MATCHED THEN
            INSERT (nm_responsavel, dt_cadastro)
            VALUES (src.nm_responsavel, SYSDATE);

        v_qt_resp := SQL%ROWCOUNT;

        -- 3. MERGE EM DIM_CLASSIFICACAO (SCD Tipo 1)
        MERGE INTO dim_classificacao dest
        USING (
            SELECT DISTINCT nm_categoria, nm_subcategoria, tp_natureza
              FROM stg_orcamento
             WHERE id_lote = p_id_lote
               AND nm_categoria IS NOT NULL
               AND nm_subcategoria IS NOT NULL
        ) src
        ON (dest.nm_categoria = src.nm_categoria AND dest.nm_subcategoria = src.nm_subcategoria)
        WHEN MATCHED THEN
            UPDATE SET dest.tp_natureza    = src.tp_natureza, 
                       dest.dt_atualizacao = SYSDATE
             WHERE dest.tp_natureza != src.tp_natureza
        WHEN NOT MATCHED THEN
            INSERT (nm_categoria, nm_subcategoria, tp_natureza, dt_atualizacao)
            VALUES (src.nm_categoria, src.nm_subcategoria, src.tp_natureza, SYSDATE);

        v_qt_class := SQL%ROWCOUNT;

        -- 4. MERGE IDEMPOTENTE EM FATO_MOVIMENTACAO
        MERGE INTO fato_movimentacao dest
        USING (
            SELECT 
                stg.id_lote,
                stg.id_origem,
                COALESCE(c_trans.sk_data, 19000101)  AS sk_data_transacao,
                COALESCE(c_comp.sk_data, 19000101)   AS sk_data_competencia,
                COALESCE(resp.sk_responsavel, -1)    AS sk_responsavel,
                COALESCE(class.sk_classificacao, -1) AS sk_classificacao,
                stg.ds_transacao AS ds_descricao,
                stg.vl_transacao AS vl_movimentacao,
                stg.fl_outlier,
                stg.fl_lag_suspeito,
                stg.ds_observacao,
                stg.hash_negocio
              FROM stg_orcamento stg
              LEFT JOIN dim_calendario c_trans
                     ON c_trans.dt_data = stg.dt_transacao
              LEFT JOIN dim_calendario c_comp
                     ON c_comp.dt_data = stg.dt_competencia
              LEFT JOIN dim_responsavel resp
                     ON resp.nm_responsavel = stg.nm_responsavel
              LEFT JOIN dim_classificacao class
                     ON class.nm_categoria = stg.nm_categoria
                    AND class.nm_subcategoria = stg.nm_subcategoria
             WHERE stg.id_lote = p_id_lote
               AND stg.id_origem IS NOT NULL
        ) src
        ON (dest.id_origem = src.id_origem)
        WHEN MATCHED THEN
            UPDATE SET
                dest.id_lote             = src.id_lote,
                dest.sk_data_transacao   = src.sk_data_transacao,
                dest.sk_data_competencia = src.sk_data_competencia,
                dest.sk_responsavel      = src.sk_responsavel,
                dest.sk_classificacao    = src.sk_classificacao,
                dest.ds_descricao        = src.ds_descricao,
                dest.vl_movimentacao     = src.vl_movimentacao,
                dest.fl_outlier          = src.fl_outlier,
                dest.fl_lag_suspeito     = src.fl_lag_suspeito,
                dest.ds_observacao       = src.ds_observacao,
                dest.hash_negocio        = src.hash_negocio,
                dest.dt_carga            = SYSTIMESTAMP
             WHERE dest.hash_negocio != src.hash_negocio
        WHEN NOT MATCHED THEN
            INSERT (
                id_lote,
                id_origem,
                sk_data_transacao,
                sk_data_competencia,
                sk_responsavel,
                sk_classificacao,
                ds_descricao,
                vl_movimentacao,
                fl_outlier,
                fl_lag_suspeito,
                ds_observacao,
                hash_negocio,
                dt_carga
            ) VALUES (
                src.id_lote,
                src.id_origem,
                src.sk_data_transacao,
                src.sk_data_competencia,
                src.sk_responsavel,
                src.sk_classificacao,
                src.ds_descricao,
                src.vl_movimentacao,
                src.fl_outlier,
                src.fl_lag_suspeito,
                src.ds_observacao,
                src.hash_negocio,
                SYSTIMESTAMP
            );

        v_qt_fato := SQL%ROWCOUNT;
        p_qt_carregados := v_qt_fato;
        COMMIT;

        -- 5. Finalizar etapa com sucesso
        pkg_log.finalizar_etapa(
            p_id_execucao_etapa      => v_id_etapa,
            p_ds_status              => pkg_log.c_status_success,
            p_qt_registros_process   => v_qt_fato,
            p_qt_registros_rejeitados => 0,
            p_ds_mensagem            => 'Carga DW concluída: ' || v_qt_fato || ' registros inseridos/atualizados na fato.'
        );

        pkg_log.info(p_id_lote, 'PKG_DW.CARREGAR_DW', 
                     'DW carregado com sucesso. Registros na Fato: ' || v_qt_fato);

    EXCEPTION
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

            pkg_log.erro(p_id_lote, 'PKG_DW.CARREGAR_DW', v_erro_msg, v_backtrace);
            RAISE;
    END carregar_dw;

    PROCEDURE carregar_dw(
        p_id_lote IN NUMBER
    ) IS
        v_c NUMBER;
    BEGIN
        carregar_dw(p_id_lote, v_c);
    END carregar_dw;

END pkg_dw;
/
