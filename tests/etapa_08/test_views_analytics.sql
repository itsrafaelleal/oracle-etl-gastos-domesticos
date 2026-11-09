-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   08 - Teste de Views Semânticas e Menor Privilégio (ORC_BI)
-- ARQUIVO: tests/etapa_08/test_views_analytics.sql
-- EXECUTOR: orc_bi no PDB FREEPDB1
-- OBJETIVO: Validar que ORC_BI acessa apenas as views VW_BI_* e não
--           possui permissão de leitura sobre as tabelas físicas do DW.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_qtd_cal           NUMBER;
    v_qtd_resp          NUMBER;
    v_qtd_class         NUMBER;
    v_qtd_fato          NUMBER;
    v_bloqueio_tabela   BOOLEAN := FALSE;
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 08: VIEWS BI E SEGURANÇA');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- 1. CONSULTAR VIEWS SEMÂNTICAS COMO USUÁRIO ORC_BI
    DBMS_OUTPUT.PUT_LINE('1. Validando acesso de leitura às Views Analíticas...');

    SELECT COUNT(*) INTO v_qtd_cal   FROM orc_owner.vw_bi_dim_calendario;
    SELECT COUNT(*) INTO v_qtd_resp  FROM orc_owner.vw_bi_dim_responsavel;
    SELECT COUNT(*) INTO v_qtd_class FROM orc_owner.vw_bi_dim_classificacao;
    SELECT COUNT(*) INTO v_qtd_fato  FROM orc_owner.vw_bi_fato_movimentacoes;

    DBMS_OUTPUT.PUT_LINE('   - VW_BI_DIM_CALENDARIO:      ' || v_qtd_cal   || ' linhas');
    DBMS_OUTPUT.PUT_LINE('   - VW_BI_DIM_RESPONSAVEL:     ' || v_qtd_resp  || ' linhas');
    DBMS_OUTPUT.PUT_LINE('   - VW_BI_DIM_CLASSIFICACAO:   ' || v_qtd_class || ' linhas');
    DBMS_OUTPUT.PUT_LINE('   - VW_BI_FATO_MOVIMENTACOES:  ' || v_qtd_fato  || ' linhas');

    IF v_qtd_cal = 0 OR v_qtd_resp = 0 OR v_qtd_class = 0 OR v_qtd_fato = 0 THEN
        RAISE_APPLICATION_ERROR(-20012, 'Falha: uma ou mais views semânticas retornaram 0 registros para ORC_BI.');
    END IF;

    -- 2. VALIDAR PRINCÍPIO DO MENOR PRIVILÉGIO (Tentar acessar tabela física)
    DBMS_OUTPUT.PUT_LINE('2. Testando restrição de acesso direto às tabelas físicas (segurança)...');
    BEGIN
        EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM orc_owner.fato_movimentacao';
        DBMS_OUTPUT.PUT_LINE('[FALHA] O usuário ORC_BI conseguiu ler diretamente a tabela física FATO_MOVIMENTACAO!');
    EXCEPTION
        WHEN OTHERS THEN
            v_bloqueio_tabela := TRUE;
            DBMS_OUTPUT.PUT_LINE('   [OK] Acesso negado com sucesso à tabela base (ORA-00942 / Menor Privilégio garantido).');
    END;

    IF NOT v_bloqueio_tabela THEN
        RAISE_APPLICATION_ERROR(-20013, 'Falha de segurança: ORC_BI tem acesso direto a tabelas físicas.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
    DBMS_OUTPUT.PUT_LINE('     Views semânticas ativas e segurança RBAC comprovada.');
    DBMS_OUTPUT.PUT_LINE('=====================================================');
END;
/
