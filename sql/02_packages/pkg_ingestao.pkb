CREATE OR REPLACE PACKAGE BODY pkg_ingestao AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_INGESTAO (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    FUNCTION carregar_arquivo(
        p_nm_arquivo IN VARCHAR2
    ) RETURN NUMBER IS
        v_id_lote       NUMBER;
        v_id_etapa      NUMBER;
        v_linhas_lidas  NUMBER := 0;
        v_hash_arquivo  RAW(32);
        v_sql_alter     VARCHAR2(500);
        v_erro_msg      VARCHAR2(4000);
        v_backtrace     VARCHAR2(4000);
    BEGIN
        -- 1. Inicia o lote de auditoria
        v_id_lote := pkg_log.iniciar_lote(p_nm_arquivo);
        v_id_etapa := pkg_log.iniciar_etapa(v_id_lote, 'INGESTAO_RAW');

        pkg_log.info(v_id_lote, 'PKG_INGESTAO.CARREGAR_ARQUIVO', 
                     'Iniciando ingestão externa para o arquivo: ' || p_nm_arquivo);

        -- 2. Altera o apontamento do arquivo na External Table via SQL Dinâmico
        v_sql_alter := 'ALTER TABLE ext_orcamento LOCATION (''' || p_nm_arquivo || ''')';
        EXECUTE IMMEDIATE v_sql_alter;

        -- 3. Carga orientada a conjuntos direto para a camada RAW
        INSERT INTO raw_orcamento_linha (
            id_lote,
            nm_arquivo,
            nr_linha,
            ds_linha,
            hash_linha,
            dt_ingestao
        )
        SELECT 
            v_id_lote,
            p_nm_arquivo,
            nr_linha,
            ds_linha,
            STANDARD_HASH(ds_linha, 'SHA256'),
            SYSTIMESTAMP
          FROM ext_orcamento;

        v_linhas_lidas := SQL%ROWCOUNT;
        COMMIT;

        -- 4. Finaliza a sub-etapa com sucesso
        pkg_log.finalizar_etapa(
            p_id_execucao_etapa      => v_id_etapa,
            p_ds_status              => pkg_log.c_status_success,
            p_qt_registros_process   => v_linhas_lidas,
            p_qt_registros_rejeitados => 0,
            p_ds_mensagem            => 'Linhas físicas ingeridas na RAW com sucesso.'
        );

        pkg_log.info(v_id_lote, 'PKG_INGESTAO.CARREGAR_ARQUIVO', 
                     'Ingestão concluída. Total de linhas físicas em RAW: ' || v_linhas_lidas);

        RETURN v_id_lote;

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

            IF v_id_lote IS NOT NULL THEN
                pkg_log.finalizar_lote(
                    p_id_lote   => v_id_lote,
                    p_ds_status => pkg_log.c_status_failed,
                    p_ds_erro   => v_erro_msg
                );
            END IF;

            pkg_log.erro(v_id_lote, 'PKG_INGESTAO.CARREGAR_ARQUIVO', v_erro_msg, v_backtrace);
            RAISE;
    END carregar_arquivo;

    PROCEDURE carregar_arquivo(
        p_nm_arquivo IN VARCHAR2,
        p_id_lote    OUT NUMBER
    ) IS
    BEGIN
        p_id_lote := carregar_arquivo(p_nm_arquivo);
    END carregar_arquivo;

END pkg_ingestao;
/
