-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   05 - Teste de Data Quality Gates (PKG_DQ)
-- ARQUIVO: tests/etapa_05/test_dq.sql
-- EXECUTOR: orc_owner no PDB FREEPDB1
-- OBJETIVO: Comprovar que o motor de Quality Gates bloqueia lotes com
--           violações de regras BLOQUEANTES (disparando ORA-20050) e
--           aprova lotes válidos sem falhas críticas.
-- =====================================================================

SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

DECLARE
    v_id_lote_defeituoso NUMBER;
    v_id_lote_limpo      NUMBER;
    v_bloqueio_detectado BOOLEAN := FALSE;
    v_falhas_bloq        NUMBER;
    v_alertas            NUMBER;
    v_bloqueado_char     CHAR(1);
    v_status_limpo       VARCHAR2(20);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=====================================================');
    DBMS_OUTPUT.PUT_LINE('INICIANDO TESTE DA ETAPA 05: DATA QUALITY GATES');
    DBMS_OUTPUT.PUT_LINE('=====================================================');

    -- CENÁRIO A: LOTE DEFEITUOSO (orcamento_teste_defeitos.csv)
    -- Possui transações duplicadas propositais -> DEVE SER BLOQUEADO!
    DBMS_OUTPUT.PUT_LINE('1. Executando Quality Gate sobre lote com inconsistências...');
    v_id_lote_defeituoso := pkg_ingestao.carregar_arquivo('orcamento_teste_defeitos.csv');
    pkg_staging.processar_lote(v_id_lote_defeituoso);

    BEGIN
        pkg_dq.executar_regras(v_id_lote_defeituoso);
        DBMS_OUTPUT.PUT_LINE('[FALHA] O Quality Gate permitiu a passagem do lote defeituoso!');
    EXCEPTION
        WHEN pkg_dq.e_quality_gate_failed THEN
            v_bloqueio_detectado := TRUE;
            DBMS_OUTPUT.PUT_LINE('   [OK] Quality Gate barrou a carga conforme esperado (ORA-20050 capturado)!');
    END;

    IF NOT v_bloqueio_detectado THEN
        RAISE_APPLICATION_ERROR(-20004, 'Falha: lote defeituoso não foi barrado pelo Quality Gate.');
    END IF;

    -- CENÁRIO B: LOTE REGULAR LIMPO (orcamento_2021_01.csv)
    -- Remessa mensal válida -> DEVE SER APROVADA!
    DBMS_OUTPUT.PUT_LINE('2. Executando Quality Gate sobre lote limpo (orcamento_2021_01.csv)...');
    v_id_lote_limpo := pkg_ingestao.carregar_arquivo('orcamento_2021_01.csv');
    pkg_staging.processar_lote(v_id_lote_limpo);

    pkg_dq.executar_regras(
        p_id_lote        => v_id_lote_limpo,
        p_fl_bloqueado   => v_bloqueado_char,
        p_qt_falhas_bloq => v_falhas_bloq,
        p_qt_alertas     => v_alertas
    );

    DBMS_OUTPUT.PUT_LINE('   Resultado Lote Limpo -> Bloqueado: ' || v_bloqueado_char || 
                         ' | Falhas Críticas: ' || v_falhas_bloq || 
                         ' | Alertas: ' || v_alertas);

    IF v_bloqueado_char = 'N' AND v_falhas_bloq = 0 THEN
        DBMS_OUTPUT.PUT_LINE('   [OK] Lote limpo aprovado com sucesso no Quality Gate!');
    ELSE
        RAISE_APPLICATION_ERROR(-20005, 'Falha: lote limpo foi indevidamente rejeitado.');
    END IF;

    DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('[OK] CRITÉRIO DE ACEITE ATINGIDO!');
    DBMS_OUTPUT.PUT_LINE('     Motor de Data Quality comprovado em ambos os cenários.');
    DBMS_OUTPUT.PUT_LINE('=====================================================');
END;
/
