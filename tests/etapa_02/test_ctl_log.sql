-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   02 - Teste de Transação Autônoma e Persistência de Logs
-- ARQUIVO: tests/etapa_02/test_ctl_log.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Comprovar que PRAGMA AUTONOMOUS_TRANSACTION em PKG_LOG
--           garante a persistência de logs mesmo após ROLLBACK da
--           transação de negócio chamadora.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_id_lote NUMBER;
    v_id_etapa NUMBER;
    v_log_count NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DE PERSISTÊNCIA AUTÔNOMA DE LOGS');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- 1. Iniciar lote e registrar mensagens via PKG_LOG
    v_id_lote := pkg_log.iniciar_lote('teste_falha_simulada.csv', HEXTORAW('A1B2C3D4'));
    v_id_etapa := pkg_log.iniciar_etapa(v_id_lote, 'ETAPA_TESTE_ROLLBACK');

    pkg_log.info(v_id_lote, 'TEST_SUITE', 'Iniciando operação de teste no lote ' || v_id_lote);
    pkg_log.warn(v_id_lote, 'TEST_SUITE', 'Sinalizando aviso de teste');
    pkg_log.erro(v_id_lote, 'TEST_SUITE', 'Simulação de erro catastrófico para teste de rollback', 'ORA-20999 em linha 42');

    -- 2. DISPARAR ROLLBACK EXPLÍCITO DA SESSÃO PRINCIPAL
    DBMS_OUTPUT.PUT_LINE('Disparando ROLLBACK na sessão chamadora...');
    ROLLBACK;

    -- 3. VALIDAR SE OS LOGS SOBREVIVERAM AO ROLLBACK
    SELECT COUNT(*)
      INTO v_log_count
      FROM ctl_log
     WHERE id_lote = v_id_lote;

    DBMS_OUTPUT.PUT_LINE('Quantidade de registros de log encontrados para o lote ' || v_id_lote || ': ' || v_log_count);

    IF v_log_count >= 3 THEN
        DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
        DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
        DBMS_OUTPUT.PUT_LINE('     Os logs persistiram com sucesso em CTL_LOG após ROLLBACK.');
        DBMS_OUTPUT.PUT_LINE('=====================================================');
    ELSE
        DBMS_OUTPUT.PUT_LINE('[ERRO] Logs não foram encontrados em CTL_LOG.');
        RAISE_APPLICATION_ERROR(-20001, 'Falha no teste: logs não sobreviveram ao ROLLBACK.');
    END IF;
END;
/
