CREATE OR REPLACE PACKAGE BODY pkg_staging AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_STAGING (Body)
       SCHEMA:  ORC_OWNER
       ===================================================================== */

    PROCEDURE processar_lote(
        p_id_lote         IN NUMBER,
        p_qt_validos      OUT NUMBER,
        p_qt_rejeitados   OUT NUMBER
    ) IS
        v_id_etapa          NUMBER;
        v_qt_rej_ruido      NUMBER := 0;
        v_qt_rej_dados      NUMBER := 0;
        v_erro_msg          VARCHAR2(4000);
        v_backtrace         VARCHAR2(4000);
    BEGIN
        v_id_etapa := pkg_log.iniciar_etapa(p_id_lote, 'STAGING_TRANSFORM');
        pkg_log.info(p_id_lote, 'PKG_STAGING.PROCESSAR_LOTE', 
                     'Iniciando processamento e padronização da Staging para o lote ' || p_id_lote);

        -- Limpar staging anterior caso seja reprocessamento do mesmo lote
        DELETE FROM stg_orcamento WHERE id_lote = p_id_lote;
        DELETE FROM stg_rejeicao WHERE id_lote = p_id_lote;

        -- 1. SEGREGAR LINHAS TOTALMENTE VAZIAS / RUÍDO DE PLANILHA (;;;;;;;;;)
        INSERT INTO stg_rejeicao (
            id_lote,
            nr_linha_origem,
            ds_linha_bruta,
            cd_motivo_rejeicao,
            ds_motivo_rejeicao,
            tp_severidade
        )
        SELECT 
            p_id_lote,
            nr_linha,
            ds_linha,
            'LINHA_VAZIA_RUIDO',
            'Linha física vazia contendo apenas delimitadores ou espaços',
            'ALERTA'
          FROM raw_orcamento_linha
         WHERE id_lote = p_id_lote
           AND nr_linha > 1
           AND (ds_linha IS NULL OR TRIM(REPLACE(ds_linha, ';', '')) IS NULL);

        v_qt_rej_ruido := SQL%ROWCOUNT;

        -- 2. SEGREGAR REGISTROS COM FALHAS CRÍTICAS DE DADOS (DATA NULA, VALOR NULO, DESCRIÇÃO NULA)
        -- Usando CTEs para recompor as linhas multipartes e extrair campos de forma orientada a conjuntos
        INSERT INTO stg_rejeicao (
            id_lote,
            nr_linha_origem,
            ds_linha_bruta,
            cd_motivo_rejeicao,
            ds_motivo_rejeicao,
            tp_severidade
        )
        WITH cte_marcacao AS (
            SELECT 
                nr_linha,
                ds_linha,
                CASE 
                    WHEN nr_linha = 1 THEN 0
                    WHEN REGEXP_LIKE(ds_linha, '^\d+;') THEN 1 
                    ELSE 0 
                END AS fl_inicio_registro
            FROM raw_orcamento_linha
            WHERE id_lote = p_id_lote
              AND nr_linha > 1
              AND ds_linha IS NOT NULL 
              AND TRIM(REPLACE(ds_linha, ';', '')) IS NOT NULL
        ),
        cte_grupos AS (
            SELECT
                nr_linha,
                ds_linha,
                SUM(fl_inicio_registro) OVER (ORDER BY nr_linha) AS grp_id
            FROM cte_marcacao
        ),
        cte_recomposta AS (
            SELECT
                grp_id,
                MIN(nr_linha) AS nr_linha_origem,
                LISTAGG(TRIM(ds_linha), ' ') WITHIN GROUP (ORDER BY nr_linha) AS ds_linha_completa
            FROM cte_grupos
            WHERE grp_id > 0
            GROUP BY grp_id
        ),
        cte_parse AS (
            SELECT
                nr_linha_origem,
                ds_linha_completa,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 1, NULL, 1) AS c_id,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 2, NULL, 1) AS c_data,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 3, NULL, 1) AS c_comp,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 4, NULL, 1) AS c_resp,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 5, NULL, 1) AS c_desc,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 6, NULL, 1) AS c_valor
            FROM cte_recomposta
        )
        SELECT 
            p_id_lote,
            nr_linha_origem,
            ds_linha_completa,
            CASE
                WHEN c_data IS NULL OR VALIDATE_CONVERSION(c_data AS DATE, 'DD/MM/YYYY') = 0 THEN 'DATA_INVALIDA_OU_NULA'
                WHEN c_valor IS NULL OR VALIDATE_CONVERSION(REPLACE(REPLACE(REPLACE(TRIM(c_valor), 'R$', ''), '.', ''), ',', '.') AS NUMBER) = 0 THEN 'VALOR_INVALIDO_OU_NULO'
                WHEN c_desc IS NULL OR TRIM(c_desc) IS NULL THEN 'DESCRICAO_NULA'
                WHEN c_resp IS NULL OR TRIM(c_resp) IS NULL THEN 'RESPONSAVEL_NULO'
                ELSE 'ERRO_ESTRUTURAL'
            END AS cd_motivo,
            CASE
                WHEN c_data IS NULL OR VALIDATE_CONVERSION(c_data AS DATE, 'DD/MM/YYYY') = 0 THEN 'Data da transação ausente ou em formato inválido'
                WHEN c_valor IS NULL OR VALIDATE_CONVERSION(REPLACE(REPLACE(REPLACE(TRIM(c_valor), 'R$', ''), '.', ''), ',', '.') AS NUMBER) = 0 THEN 'Valor financeiro ausente ou não numérico'
                WHEN c_desc IS NULL OR TRIM(c_desc) IS NULL THEN 'Descrição do lançamento ausente ou em branco'
                WHEN c_resp IS NULL OR TRIM(c_resp) IS NULL THEN 'Identificação do responsável ausente'
                ELSE 'Inconsistência nos campos da transação'
            END AS ds_motivo,
            'ERRO' AS tp_severidade
          FROM cte_parse
         WHERE (c_data IS NULL OR VALIDATE_CONVERSION(c_data AS DATE, 'DD/MM/YYYY') = 0)
            OR (c_valor IS NULL OR VALIDATE_CONVERSION(REPLACE(REPLACE(REPLACE(TRIM(c_valor), 'R$', ''), '.', ''), ',', '.') AS NUMBER) = 0)
            OR (c_desc IS NULL OR TRIM(c_desc) IS NULL)
            OR (c_resp IS NULL OR TRIM(c_resp) IS NULL);

        v_qt_rej_dados := SQL%ROWCOUNT;
        p_qt_rejeitados := v_qt_rej_ruido + v_qt_rej_dados;

        -- 3. CARREGAR REGISTROS VÁLIDOS E PADRONIZADOS EM STG_ORCAMENTO
        INSERT INTO stg_orcamento (
            id_lote,
            nr_linha_origem,
            id_origem,
            dt_transacao,
            dt_competencia,
            nm_responsavel,
            ds_transacao,
            vl_transacao,
            nm_categoria,
            nm_subcategoria,
            tp_natureza,
            ds_observacao,
            fl_outlier,
            fl_lag_suspeito,
            hash_negocio,
            dt_processamento
        )
        WITH cte_marcacao AS (
            SELECT 
                nr_linha,
                ds_linha,
                CASE 
                    WHEN nr_linha = 1 THEN 0
                    WHEN REGEXP_LIKE(ds_linha, '^\d+;') THEN 1 
                    ELSE 0 
                END AS fl_inicio_registro
            FROM raw_orcamento_linha
            WHERE id_lote = p_id_lote
              AND nr_linha > 1
              AND ds_linha IS NOT NULL 
              AND TRIM(REPLACE(ds_linha, ';', '')) IS NOT NULL
        ),
        cte_grupos AS (
            SELECT
                nr_linha,
                ds_linha,
                SUM(fl_inicio_registro) OVER (ORDER BY nr_linha) AS grp_id
            FROM cte_marcacao
        ),
        cte_recomposta AS (
            SELECT
                grp_id,
                MIN(nr_linha) AS nr_linha_origem,
                LISTAGG(TRIM(ds_linha), ' ') WITHIN GROUP (ORDER BY nr_linha) AS ds_linha_completa
            FROM cte_grupos
            WHERE grp_id > 0
            GROUP BY grp_id
        ),
        cte_parse AS (
            SELECT
                nr_linha_origem,
                ds_linha_completa,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 1, NULL, 1) AS c_id,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 2, NULL, 1) AS c_data,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 3, NULL, 1) AS c_comp,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 4, NULL, 1) AS c_resp,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 5, NULL, 1) AS c_desc,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 6, NULL, 1) AS c_valor,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 7, NULL, 1) AS c_cat,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 8, NULL, 1) AS c_subcat,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 9, NULL, 1) AS c_tipo,
                REGEXP_SUBSTR(';' || ds_linha_completa || ';', ';([^;]*)', 1, 10, NULL, 1) AS c_obs
            FROM cte_recomposta
        ),
        cte_validos_brutos AS (
            SELECT
                nr_linha_origem,
                TO_NUMBER(c_id DEFAULT NULL ON CONVERSION ERROR) AS id_origem,
                TO_DATE(c_data, 'DD/MM/YYYY') AS dt_transacao,
                -- Tratamento de competência: extrai mês e ano de números como 22.023, 102.024 ou 62.025
                CASE 
                    WHEN LENGTH(REPLACE(c_comp, '.', '')) >= 5 THEN
                        TO_DATE('01/' || 
                                LPAD(SUBSTR(REPLACE(c_comp, '.', ''), 1, LENGTH(REPLACE(c_comp, '.', '')) - 4), 2, '0') || '/' || 
                                SUBSTR(REPLACE(c_comp, '.', ''), -4), 'DD/MM/YYYY')
                    ELSE
                        TO_DATE(c_data, 'DD/MM/YYYY')
                END AS dt_competencia,
                TRIM(c_resp) AS nm_responsavel,
                REGEXP_REPLACE(TRIM(c_desc), ' {2,}', ' ') AS ds_transacao,
                -- Normalização monetária: remove R$, remove separador de milhar ponto, troca vírgula decimal por ponto
                TO_NUMBER(REPLACE(REPLACE(REPLACE(TRIM(c_valor), 'R$', ''), '.', ''), ',', '.')) AS vl_transacao,
                COALESCE(TRIM(c_cat), 'Outros') AS nm_categoria,
                COALESCE(TRIM(c_subcat), 'Diversos') AS nm_subcategoria,
                COALESCE(TRIM(UPPER(c_tipo)), 'OPEX') AS tp_natureza,
                TRIM(c_obs) AS ds_observacao
            FROM cte_parse
            WHERE c_data IS NOT NULL 
              AND VALIDATE_CONVERSION(c_data AS DATE, 'DD/MM/YYYY') = 1
              AND c_valor IS NOT NULL 
              AND VALIDATE_CONVERSION(REPLACE(REPLACE(REPLACE(TRIM(c_valor), 'R$', ''), '.', ''), ',', '.') AS NUMBER) = 1
              AND c_desc IS NOT NULL AND TRIM(c_desc) IS NOT NULL
              AND c_resp IS NOT NULL AND TRIM(c_resp) IS NOT NULL
        ),
        cte_metricas AS (
            SELECT 
                nr_linha_origem,
                id_origem,
                dt_transacao,
                dt_competencia,
                nm_responsavel,
                ds_transacao,
                vl_transacao,
                nm_categoria,
                nm_subcategoria,
                tp_natureza,
                ds_observacao,
                -- Window function para identificar outliers estatísticos:
                -- Utiliza a média Jackknife / Leave-One-Out (exclui o próprio valor da média para evitar distorção)
                CASE 
                    WHEN COUNT(*) OVER (PARTITION BY nm_subcategoria) > 1 
                         AND vl_transacao > 4 * ((SUM(vl_transacao) OVER (PARTITION BY nm_subcategoria) - vl_transacao) / 
                                                 (COUNT(*) OVER (PARTITION BY nm_subcategoria) - 1)) THEN 'S'
                    WHEN COUNT(*) OVER (PARTITION BY nm_subcategoria) = 1 
                         AND vl_transacao > 4 * ((SUM(vl_transacao) OVER () - vl_transacao) / 
                                                 NULLIF(COUNT(*) OVER () - 1, 0)) THEN 'S'
                    ELSE 'N'
                END AS fl_outlier,
                -- Regra de lag: faturas com mais de 12 meses de diferença ou lag negativo anômalo
                CASE 
                    WHEN MONTHS_BETWEEN(dt_competencia, TRUNC(dt_transacao, 'MM')) > 12 
                      OR MONTHS_BETWEEN(dt_competencia, TRUNC(dt_transacao, 'MM')) < -1 THEN 'S'
                    ELSE 'N'
                END AS fl_lag_suspeito,
                -- Hash de negócio para MERGE idempotente na camada DW
                STANDARD_HASH(
                    COALESCE(TO_CHAR(id_origem), '') || '|' ||
                    TO_CHAR(dt_transacao, 'YYYY-MM-DD') || '|' ||
                    nm_responsavel || '|' ||
                    TO_CHAR(vl_transacao, '999999990.99') || '|' ||
                    ds_transacao, 
                    'SHA256'
                ) AS hash_negocio
            FROM cte_validos_brutos
        )
        SELECT 
            p_id_lote,
            nr_linha_origem,
            id_origem,
            dt_transacao,
            dt_competencia,
            nm_responsavel,
            ds_transacao,
            vl_transacao,
            nm_categoria,
            nm_subcategoria,
            tp_natureza,
            ds_observacao,
            fl_outlier,
            fl_lag_suspeito,
            hash_negocio,
            SYSTIMESTAMP
          FROM cte_metricas;

        p_qt_validos := SQL%ROWCOUNT;
        COMMIT;

        -- 4. Finalizar etapa com métricas de sucesso
        pkg_log.finalizar_etapa(
            p_id_execucao_etapa      => v_id_etapa,
            p_ds_status              => pkg_log.c_status_success,
            p_qt_registros_process   => p_qt_validos,
            p_qt_registros_rejeitados => p_qt_rejeitados,
            p_ds_mensagem            => 'Staging processada: ' || p_qt_validos || ' válidos, ' || p_qt_rejeitados || ' rejeitados.'
        );

        pkg_log.info(p_id_lote, 'PKG_STAGING.PROCESSAR_LOTE', 
                     'Staging finalizada. Válidos: ' || p_qt_validos || ' | Rejeitados: ' || p_qt_rejeitados);

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

            pkg_log.erro(p_id_lote, 'PKG_STAGING.PROCESSAR_LOTE', v_erro_msg, v_backtrace);
            RAISE;
    END processar_lote;

    PROCEDURE processar_lote(
        p_id_lote IN NUMBER
    ) IS
        v_v NUMBER;
        v_r NUMBER;
    BEGIN
        processar_lote(p_id_lote, v_v, v_r);
    END processar_lote;

END pkg_staging;
/
