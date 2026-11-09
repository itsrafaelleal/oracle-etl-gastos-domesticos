-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   07 - Teste de Orquestração Mestre e Reprocessamento (PKG_PIPELINE)
-- ARQUIVO: tests/etapa_07/test_pipeline.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Validar execução completa ponta a ponta, tratamento de falhas
--           com status FAILED no lote e reprocessamento a partir da RAW.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_id_lote_ok        NUMBER;
    v_id_lote_fail      NUMBER;
    v_status_lote       VARCHAR2(20);
    v_erro_lote         VARCHAR2(4000);
    v_lidas             NUMBER;
    v_validas           NUMBER;
    v_carregadas        NUMBER;
    v_falha_bloqueada   BOOLEAN := FALSE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 07: ORQUESTRAÇÃO DO PIPELINE');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- CENÁRIO 1: EXECUÇÃO PONTA A PONTA DE LOTE REGULAR (orcamento_2021_03.csv)
    DBMS_OUTPUT.PUT_LINE('1. Executando pipeline ponta a ponta para remessa regular...');
    v_id_lote_ok := pkg_pipeline.executar_carga_arquivo('orcamento_2021_03.csv');
    DBMS_OUTPUT.PUT_LINE('   Lote gerado: ' || v_id_lote_ok);

    SELECT ds_status, qt_linhas_lidas, qt_linhas_validas, qt_linhas_carregadas
      INTO v_status_lote, v_lidas, v_validas, v_carregadas
      FROM ctl_lote
     WHERE id_lote = v_id_lote_ok;

    DBMS_OUTPUT.PUT_LINE('   Status Lote: ' || v_status_lote || 
                         ' | Lidas: ' || v_lidas || 
                         ' | Válidas: ' || v_validas || 
                         ' | Carregadas no DW: ' || v_carregadas);

    IF v_status_lote != 'SUCCESS' THEN
        RAISE_APPLICATION_ERROR(-20008, 'Falha: lote regular não finalizou com status SUCCESS.');
    END IF;

    -- CENÁRIO 2: FALHA INTENCIONAL COM AUDITORIA (orcamento_teste_defeitos.csv)
    DBMS_OUTPUT.PUT_LINE('2. Testando bloqueio e persistência de status FAILED em lote defeituoso...');
    BEGIN
        v_id_lote_fail := pkg_pipeline.executar_carga_arquivo('orcamento_teste_defeitos.csv');
    EXCEPTION
        WHEN pkg_dq.e_quality_gate_failed THEN
            v_falha_bloqueada := TRUE;
            DBMS_OUTPUT.PUT_LINE('   Exceção esperada disparada pelo Quality Gate.');
    END;

    IF NOT v_falha_bloqueada THEN
        RAISE_APPLICATION_ERROR(-20009, 'Falha: lote defeituoso não disparou exceção de Quality Gate.');
    END IF;

    -- Localizar o último lote defeituoso gerado
    SELECT id_lote, ds_status, ds_erro
      INTO v_id_lote_fail, v_status_lote, v_erro_lote
      FROM (SELECT id_lote, ds_status, ds_erro FROM ctl_lote WHERE nm_arquivo_origem = 'orcamento_teste_defeitos.csv' ORDER BY id_lote DESC)
     WHERE ROWNUM = 1;

    DBMS_OUTPUT.PUT_LINE('   Lote defeituoso ID: ' || v_id_lote_fail || ' | Status: ' || v_status_lote);
    DBMS_OUTPUT.PUT_LINE('   Mensagem de erro registrada: ' || SUBSTR(v_erro_lote, 1, 80) || '...');

    IF v_status_lote != 'FAILED' OR v_erro_lote IS NULL THEN
        RAISE_APPLICATION_ERROR(-20010, 'Falha: lote com defeito não registrou status FAILED ou mensagem de erro.');
    END IF;

    -- CENÁRIO 3: REPROCESSAMENTO SEGURO A PARTIR DA CAMADA RAW
    DBMS_OUTPUT.PUT_LINE('3. Testando reprocessamento a partir da RAW para o lote ' || v_id_lote_ok || '...');
    pkg_pipeline.reprocessar_lote(v_id_lote_ok);

    SELECT ds_status INTO v_status_lote FROM ctl_lote WHERE id_lote = v_id_lote_ok;
    DBMS_OUTPUT.PUT_LINE('   Status pós-reprocessamento: ' || v_status_lote);

    IF v_status_lote != 'SUCCESS' THEN
        RAISE_APPLICATION_ERROR(-20011, 'Falha: reprocessamento não retornou SUCCESS.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
    DBMS_OUTPUT.PUT_LINE('     Orquestrador PKG_PIPELINE validado em todos os cenários.');
    DBMS_OUTPUT.PUT_LINE('=====================================================');
END;
/
