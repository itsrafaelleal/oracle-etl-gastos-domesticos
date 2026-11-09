-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   03 - Teste de Ingestão de Dados (External Table e RAW)
-- ARQUIVO: tests/etapa_03/test_ingestao.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Validar se a ingestão via PKG_INGESTAO preserva com 100%
--           de fidelidade todas as linhas físicas do CSV na camada RAW.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_arquivo       CONSTANT VARCHAR2(100) := 'orcamento_teste_defeitos.csv';
    v_id_lote       NUMBER;
    v_qtd_raw       NUMBER;
    v_qtd_ext       NUMBER;
    v_status_etapa  VARCHAR2(20);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 03: INGESTÃO EXTERNAL -> RAW');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- 1. Obter contagem de linhas físicas diretamente da External Table
    EXECUTE IMMEDIATE 'ALTER TABLE ext_orcamento LOCATION (''' || v_arquivo || ''')';
    SELECT COUNT(*) INTO v_qtd_ext FROM ext_orcamento;
    DBMS_OUTPUT.PUT_LINE('Linhas físicas detectadas na External Table: ' || v_qtd_ext);

    -- 2. Executar procedure de ingestão
    v_id_lote := pkg_ingestao.carregar_arquivo(v_arquivo);
    DBMS_OUTPUT.PUT_LINE('Lote de ingestão gerado: ' || v_id_lote);

    -- 3. Verificar quantidade de registros gravados na tabela RAW
    SELECT COUNT(*) INTO v_qtd_raw
      FROM raw_orcamento_linha
     WHERE id_lote = v_id_lote;
    DBMS_OUTPUT.PUT_LINE('Linhas persistidas na camada RAW: ' || v_qtd_raw);

    -- 4. Verificar status da etapa em CTL_EXECUCAO_ETAPA
    SELECT ds_status INTO v_status_etapa
      FROM ctl_execucao_etapa
     WHERE id_lote = v_id_lote
       AND nm_etapa = 'INGESTAO_RAW';

    DBMS_OUTPUT.PUT_LINE('Status registrado na etapa: ' || v_status_etapa);

    -- 5. Critério de Aceite: v_qtd_raw == v_qtd_ext e status == SUCCESS
    IF v_qtd_raw = v_qtd_ext AND v_qtd_raw > 0 AND v_status_etapa = 'SUCCESS' THEN
        DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
        DBMS_OUTPUT.PUT_LINE('     Fidelidade total: 100% das linhas (' || v_qtd_raw || ') foram ingeridas em RAW.');
        DBMS_OUTPUT.PUT_LINE('=====================================================');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERRO] Divergência na contagem ou falha na etapa.');
        RAISE_APPLICATION_ERROR(-20002, 'Falha no teste de ingestão da Etapa 03.');
    END IF;
END;
/
