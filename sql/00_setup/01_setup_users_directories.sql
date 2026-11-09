-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   00 - Setup de Ambiente
-- ARQUIVO: sql/00_setup/01_setup_users_directories.sql
-- EXECUTOR: SYSTEM ou DBA no PDB FREEPDB1
-- OBJETIVO: Criar schemas segregados (ORC_OWNER, ORC_BI), diretórios
--           e conceder privilégios necessários para o pipeline.
-- =====================================================================

WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK;
SET ECHO ON
SET SERVEROUTPUT ON

-- 1. Criação do Usuário Dono (ORC_OWNER)
DECLARE
    v_user_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_user_exists FROM all_users WHERE username = 'ORC_OWNER';
    IF v_user_exists = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER orc_owner IDENTIFIED BY "OrcOwner_2026_Secure!" DEFAULT TABLESPACE users QUOTA UNLIMITED ON users';
        DBMS_OUTPUT.PUT_LINE('Usuário ORC_OWNER criado com sucesso.');
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER orc_owner IDENTIFIED BY "OrcOwner_2026_Secure!" QUOTA UNLIMITED ON users ACCOUNT UNLOCK';
        DBMS_OUTPUT.PUT_LINE('Usuário ORC_OWNER já existe. Senha e quota atualizadas.');
    END IF;
END;
/

-- Privilégios para ORC_OWNER
GRANT CREATE SESSION TO orc_owner;
GRANT CREATE TABLE TO orc_owner;
GRANT CREATE VIEW TO orc_owner;
GRANT CREATE PROCEDURE TO orc_owner;
GRANT CREATE SEQUENCE TO orc_owner;
GRANT CREATE SYNONYM TO orc_owner;
GRANT CREATE TYPE TO orc_owner;
GRANT CREATE MATERIALIZED VIEW TO orc_owner;
GRANT UNLIMITED TABLESPACE TO orc_owner;
-- DBMS_XPLAN já possui permissão de EXECUTE pública (PUBLIC) no Oracle por padrão.

-- 2. Criação do Usuário de Leitura para Power BI (ORC_BI)
DECLARE
    v_user_exists NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_user_exists FROM all_users WHERE username = 'ORC_BI';
    IF v_user_exists = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER orc_bi IDENTIFIED BY "OrcBi_2026_Secure!" DEFAULT TABLESPACE users';
        DBMS_OUTPUT.PUT_LINE('Usuário ORC_BI criado com sucesso.');
    ELSE
        EXECUTE IMMEDIATE 'ALTER USER orc_bi IDENTIFIED BY "OrcBi_2026_Secure!" ACCOUNT UNLOCK';
        DBMS_OUTPUT.PUT_LINE('Usuário ORC_BI já existe. Senha atualizada.');
    END IF;
END;
/

GRANT CREATE SESSION TO orc_bi;

-- 3. Criação dos Diretórios Oracle para Ingestão e Logs de External Table
CREATE OR REPLACE DIRECTORY DIR_ORC_INBOX AS '/opt/orc/inbox';
CREATE OR REPLACE DIRECTORY DIR_ORC_LOG AS '/opt/orc/log';

-- 4. Concessão de Privilégios sobre os Diretórios para ORC_OWNER
GRANT READ ON DIRECTORY DIR_ORC_INBOX TO orc_owner;
GRANT READ, WRITE ON DIRECTORY DIR_ORC_LOG TO orc_owner;

PROMPT =====================================================================
PROMPT Setup de schemas e diretórios concluído com sucesso no PDB.
PROMPT =====================================================================
