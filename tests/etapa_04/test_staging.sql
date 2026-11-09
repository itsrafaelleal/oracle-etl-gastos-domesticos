-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   04 - Teste de Staging (Recomposição, Parse e Rejeições)
-- ARQUIVO: tests/etapa_04/test_staging.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Validar se PKG_STAGING recompõe registros partidos por quebras
--           de linha, segrega rejeições e normaliza registros válidos.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_arquivo       CONSTANT VARCHAR2(100) := 'orcamento_teste_defeitos.csv';
    v_id_lote       NUMBER;
    v_qtd_raw       NUMBER;
    v_validos       NUMBER;
    v_rejeitados    NUMBER;
    v_recompostos   NUMBER;
    v_ruido         NUMBER;
    v_val_nulo      NUMBER;
    v_outliers      NUMBER;
    v_status_etapa  VARCHAR2(20);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 04: STAGING E RECOMPOSIÇÃO');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- 1. Ingerir lote com defeitos
    v_id_lote := pkg_ingestao.carregar_arquivo(v_arquivo);
    SELECT COUNT(*) INTO v_qtd_raw FROM raw_orcamento_linha WHERE id_lote = v_id_lote;
    DBMS_OUTPUT.PUT_LINE('1. Linhas físicas em RAW para o lote ' || v_id_lote || ': ' || v_qtd_raw);

    -- 2. Processar Staging via PKG_STAGING
    pkg_staging.processar_lote(v_id_lote, v_validos, v_rejeitados);
    DBMS_OUTPUT.PUT_LINE('2. Resultado Staging -> Válidos: ' || v_validos || ' | Rejeitados: ' || v_rejeitados);

    -- 3. Validar se os 49 registros com quebra de linha foram recompostos em 1 única linha cada
    SELECT COUNT(*) INTO v_recompostos
      FROM stg_orcamento
     WHERE id_lote = v_id_lote
       AND ds_transacao LIKE '%Continuação%';
    DBMS_OUTPUT.PUT_LINE('3. Registros partidos recompostos com sucesso: ' || v_recompostos || ' (esperado: 49)');

    -- 4. Validar segregação de ruído de linhas vazias (;;;;;;;;;)
    SELECT COUNT(*) INTO v_ruido
      FROM stg_rejeicao
     WHERE id_lote = v_id_lote
       AND cd_motivo_rejeicao = 'LINHA_VAZIA_RUIDO';
    DBMS_OUTPUT.PUT_LINE('4. Linhas vazias/ruído rejeitadas: ' || v_ruido || ' (esperado: 15)');

    -- 5. Validar segregação de registros com valor nulo
    SELECT COUNT(*) INTO v_val_nulo
      FROM stg_rejeicao
     WHERE id_lote = v_id_lote
       AND cd_motivo_rejeicao = 'VALOR_INVALIDO_OU_NULO';
    DBMS_OUTPUT.PUT_LINE('5. Registros com valor ausente rejeitados: ' || v_val_nulo || ' (esperado: 5)');

    -- 6. Validar detecção de outliers estatísticos
    SELECT COUNT(*) INTO v_outliers
      FROM stg_orcamento
     WHERE id_lote = v_id_lote
       AND fl_outlier = 'S';
    DBMS_OUTPUT.PUT_LINE('6. Outliers detectados pela Window Function: ' || v_outliers || ' (esperado: >= 1)');

    -- 7. Checar status da etapa
    SELECT ds_status INTO v_status_etapa
      FROM ctl_execucao_etapa
     WHERE id_lote = v_id_lote
       AND nm_etapa = 'STAGING_TRANSFORM';

    -- Critérios de aceite consolidados:
    IF v_recompostos = 49 AND v_ruido = 15 AND v_val_nulo = 5 AND v_outliers >= 1 AND v_status_etapa = 'SUCCESS' THEN
        DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
        DBMS_OUTPUT.PUT_LINE('     Recomposição, tipagem, parse e segregação validados com 100% de precisão.');
        DBMS_OUTPUT.PUT_LINE('=====================================================');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERRO] Falha nos critérios de aceite da Staging.');
        RAISE_APPLICATION_ERROR(-20003, 'Falha no teste de staging da Etapa 04.');
    END IF;
END;
/
