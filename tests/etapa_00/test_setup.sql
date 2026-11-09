-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   00 - Teste de Validação do Setup
-- ARQUIVO: tests/etapa_00/test_setup.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Validar se ORC_OWNER consegue conectar, possui privilégios
--           e tem acesso aos diretórios DIR_ORC_INBOX e DIR_ORC_LOG.
-- =====================================================================

WHENEVER SQLERROR EXIT FAILURE ROLLBACK;
SET SERVEROUTPUT ON
SET FEEDBACK OFF

DECLARE
    v_user VARCHAR2(128);
    v_inbox_count NUMBER := 0;
    v_log_count NUMBER := 0;
    v_priv_count NUMBER := 0;
    v_errors NUMBER := 0;
BEGIN
    SELECT USER INTO v_user FROM dual;
    DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('1. Validando usuário conectado: ' || v_user);
    IF v_user != 'ORC_OWNER' THEN
        DBMS_OUTPUT.PUT_LINE('ERRO: Esperado conectar como ORC_OWNER, conectado como ' || v_user);
        v_errors := v_errors + 1;
    ELSE
        DBMS_OUTPUT.PUT_LINE('   [OK] Conectado corretamente como ORC_OWNER');
    END IF;

    DBMS_OUTPUT.PUT_LINE('2. Validando privilégios sobre diretórios Oracle:');
    SELECT COUNT(*) INTO v_inbox_count
      FROM all_tab_privs
     WHERE table_name = 'DIR_ORC_INBOX'
       AND grantee = 'ORC_OWNER'
       AND privilege = 'READ';

    IF v_inbox_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('   [OK] Leitura em DIR_ORC_INBOX concedida');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   [ERRO] Falta privilégio READ em DIR_ORC_INBOX');
        v_errors := v_errors + 1;
    END IF;

    SELECT COUNT(*) INTO v_log_count
      FROM all_tab_privs
     WHERE table_name = 'DIR_ORC_LOG'
       AND grantee = 'ORC_OWNER'
       AND privilege IN ('READ', 'WRITE');

    IF v_log_count >= 2 THEN
        DBMS_OUTPUT.PUT_LINE('   [OK] Leitura e escrita em DIR_ORC_LOG concedidas');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   [ERRO] Faltam privilégios em DIR_ORC_LOG (encontrados: ' || v_log_count || ')');
        v_errors := v_errors + 1;
    END IF;

    DBMS_OUTPUT.PUT_LINE('3. Validando privilégios de sistema para DDL/DML:');
    SELECT COUNT(*) INTO v_priv_count
      FROM user_sys_privs
     WHERE privilege IN ('CREATE TABLE', 'CREATE PROCEDURE', 'CREATE VIEW', 'CREATE SEQUENCE');

    IF v_priv_count >= 4 THEN
        DBMS_OUTPUT.PUT_LINE('   [OK] Privilégios essenciais (TABLE, PROCEDURE, VIEW, SEQUENCE) concedidos');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   [ERRO] Privilégios de sistema incompletos (encontrados: ' || v_priv_count || ')');
        v_errors := v_errors + 1;
    END IF;

    DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
    IF v_errors = 0 THEN
        DBMS_OUTPUT.PUT_LINE('STATUS FINAL: ETAPA 00 VALIDADA COM SUCESSO! (100% OK)');
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
    ELSE
        DBMS_OUTPUT.PUT_LINE('STATUS FINAL: ' || v_errors || ' ERRO(S) ENCONTRADO(S).');
        DBMS_OUTPUT.PUT_LINE('----------------------------------------------------');
        RAISE_APPLICATION_ERROR(-20000, 'Falha no teste de setup da Etapa 00.');
    END IF;
END;
/
EXIT;
