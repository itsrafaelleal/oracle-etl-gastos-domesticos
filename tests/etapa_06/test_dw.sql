-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   06 - Teste de Carga Dimensional e Idempotência (Star Schema)
-- ARQUIVO: tests/etapa_06/test_dw.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Validar se a carga do DW em FATO_MOVIMENTACAO garante integridade
--           referencial total (0 FKs órfãs) e idempotência estrita via MERGE.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_arquivo           CONSTANT VARCHAR2(100) := 'orcamento_2021_01.csv';
    v_id_lote           NUMBER;
    v_qt_validos        NUMBER;
    v_qt_rejeitados     NUMBER;
    v_qt_carregados_1   NUMBER;
    v_qt_carregados_2   NUMBER;
    v_total_fato_1      NUMBER;
    v_total_fato_2      NUMBER;
    v_orfas_trans       NUMBER;
    v_orfas_comp        NUMBER;
    v_orfas_resp        NUMBER;
    v_orfas_class       NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 06: CARGA DW E IDEMPOTÊNCIA');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- 1. Ingestão e Staging da remessa regular
    v_id_lote := pkg_ingestao.carregar_arquivo(v_arquivo);
    pkg_staging.processar_lote(v_id_lote, v_qt_validos, v_qt_rejeitados);
    DBMS_OUTPUT.PUT_LINE('1. Staging processada -> Válidos: ' || v_qt_validos || ' | Rejeitados: ' || v_qt_rejeitados);

    -- 2. Primeira Carga no Data Warehouse
    pkg_dw.carregar_dw(v_id_lote, v_qt_carregados_1);
    SELECT COUNT(*) INTO v_total_fato_1 FROM fato_movimentacao;
    DBMS_OUTPUT.PUT_LINE('2. Primeira carga DW finalizada -> Registros na Fato: ' || v_total_fato_1);

    -- 3. Validação de Integridade Referencial (0 FKs órfãs)
    SELECT COUNT(*) INTO v_orfas_trans FROM fato_movimentacao WHERE sk_data_transacao NOT IN (SELECT sk_data FROM dim_calendario);
    SELECT COUNT(*) INTO v_orfas_comp  FROM fato_movimentacao WHERE sk_data_competencia NOT IN (SELECT sk_data FROM dim_calendario);
    SELECT COUNT(*) INTO v_orfas_resp  FROM fato_movimentacao WHERE sk_responsavel NOT IN (SELECT sk_responsavel FROM dim_responsavel);
    SELECT COUNT(*) INTO v_orfas_class FROM fato_movimentacao WHERE sk_classificacao NOT IN (SELECT sk_classificacao FROM dim_classificacao);

    DBMS_OUTPUT.PUT_LINE('3. Verificação de Integridade Referencial:');
    DBMS_OUTPUT.PUT_LINE('   - Órfãs Data Transação:   ' || v_orfas_trans);
    DBMS_OUTPUT.PUT_LINE('   - Órfãs Data Competência: ' || v_orfas_comp);
    DBMS_OUTPUT.PUT_LINE('   - Órfãs Responsável:      ' || v_orfas_resp);
    DBMS_OUTPUT.PUT_LINE('   - Órfãs Classificação:    ' || v_orfas_class);

    IF (v_orfas_trans + v_orfas_comp + v_orfas_resp + v_orfas_class) > 0 THEN
        RAISE_APPLICATION_ERROR(-20006, 'Falha: FKs órfãs encontradas na tabela fato.');
    END IF;

    -- 4. TESTE DE IDEMPOTÊNCIA: Executar a carga do mesmo lote pela segunda vez
    DBMS_OUTPUT.PUT_LINE('4. Executando segunda carga do mesmo lote para testar idempotência...');
    pkg_dw.carregar_dw(v_id_lote, v_qt_carregados_2);
    SELECT COUNT(*) INTO v_total_fato_2 FROM fato_movimentacao;
    DBMS_OUTPUT.PUT_LINE('   Total de linhas na Fato após 2ª execução: ' || v_total_fato_2 || ' (anterior: ' || v_total_fato_1 || ')');

    IF v_total_fato_1 = v_total_fato_2 AND v_total_fato_1 > 0 THEN
        DBMS_OUTPUT.PUT_LINE('   [OK] Idempotência comprovada: nenhuma linha duplicada!');
    ELSE
        RAISE_APPLICATION_ERROR(-20007, 'Falha: a segunda execução duplicou linhas na tabela fato.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
    DBMS_OUTPUT.PUT_LINE('     Star Schema populado, FKs íntegras e MERGE idempotente validado.');
    DBMS_OUTPUT.PUT_LINE('=====================================================');
END;
/
