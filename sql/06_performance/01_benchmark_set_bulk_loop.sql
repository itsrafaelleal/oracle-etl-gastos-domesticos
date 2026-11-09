-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   09 - Benchmark de Performance: Loop Linha a Linha vs. FORALL vs. SQL Orientado a Conjuntos
-- ARQUIVO: sql/06_performance/01_benchmark_set_bulk_loop.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Comprovar empiricamente a superioridade do SQL orientado a
--           conjuntos frente ao processamento procedural linha a linha
--           e a operações em lote com BULK COLLECT / FORALL.
-- =====================================================================

SET SERVEROUTPUT ON;
SET TIMING OFF;

-- Tabela temporária de teste para benchmarking isolado
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE t_benchmark_teste PURGE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE t_benchmark_teste (
    id_registro   NUMBER,
    ds_texto      VARCHAR2(100),
    vl_numero     NUMBER(12,2),
    dt_criacao    DATE
);

DECLARE
    c_qtd_linhas    CONSTANT NUMBER := 50000;
    v_inicio        NUMBER;
    v_tempo_loop    NUMBER;
    v_tempo_bulk    NUMBER;
    v_tempo_set     NUMBER;

    -- Tipos para BULK COLLECT
    TYPE t_rec IS RECORD (
        id_registro NUMBER,
        ds_texto    VARCHAR2(100),
        vl_numero   NUMBER(12,2),
        dt_criacao  DATE
    );
    TYPE t_tab IS TABLE OF t_rec;
    v_dados t_tab;

    CURSOR c_dados IS
        SELECT LEVEL AS id,
               'Transacao Teste Linha ' || LEVEL AS ds,
               ROUND(DBMS_RANDOM.VALUE(10, 1500), 2) AS vl,
               DATE '2023-01-01' + MOD(LEVEL, 1000) AS dt
          FROM dual
       CONNECT BY LEVEL <= c_qtd_linhas;

BEGIN
    DBMS_OUTPUT.PUT_LINE('====================================================================');
    DBMS_OUTPUT.PUT_LINE('BENCHMARK ORACLE: ' || c_qtd_linhas || ' REGISTROS');
    DBMS_OUTPUT.PUT_LINE('Comparando Cursor Linha a Linha vs. FORALL/BULK COLLECT vs. SQL Puro');
    DBMS_OUTPUT.PUT_LINE('====================================================================');

    -- -------------------------------------------------------------
    -- MÉTODO 1: LOOP PROCEDURAL LINHA A LINHA (Cursor com INSERT unitário)
    -- -------------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE t_benchmark_teste';
    v_inicio := DBMS_UTILITY.GET_TIME;

    FOR r IN c_dados LOOP
        INSERT INTO t_benchmark_teste (id_registro, ds_texto, vl_numero, dt_criacao)
        VALUES (r.id, r.ds, r.vl, r.dt);
    END LOOP;
    COMMIT;

    v_tempo_loop := (DBMS_UTILITY.GET_TIME - v_inicio) / 100.0;
    DBMS_OUTPUT.PUT_LINE('1. Loop Linha a Linha (Slow-by-Slow): ' || TO_CHAR(v_tempo_loop, 'FM990.00') || ' segundos');

    -- -------------------------------------------------------------
    -- MÉTODO 2: PL/SQL BULK COLLECT + FORALL (Lotes de 1.000)
    -- -------------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE t_benchmark_teste';
    v_inicio := DBMS_UTILITY.GET_TIME;

    OPEN c_dados;
    LOOP
        FETCH c_dados BULK COLLECT INTO v_dados LIMIT 1000;
        EXIT WHEN v_dados.COUNT = 0;

        FORALL i IN 1..v_dados.COUNT
            INSERT INTO t_benchmark_teste VALUES v_dados(i);
    END LOOP;
    CLOSE c_dados;
    COMMIT;

    v_tempo_bulk := (DBMS_UTILITY.GET_TIME - v_inicio) / 100.0;
    DBMS_OUTPUT.PUT_LINE('2. BULK COLLECT + FORALL (Batch 1000): ' || TO_CHAR(v_tempo_bulk, 'FM990.00') || ' segundos');

    -- -------------------------------------------------------------
    -- MÉTODO 3: SQL ORIENTADO A CONJUNTOS (Set-Based INSERT /*+ APPEND */)
    -- -------------------------------------------------------------
    EXECUTE IMMEDIATE 'TRUNCATE TABLE t_benchmark_teste';
    v_inicio := DBMS_UTILITY.GET_TIME;

    INSERT /*+ APPEND */ INTO t_benchmark_teste (id_registro, ds_texto, vl_numero, dt_criacao)
    SELECT LEVEL,
           'Transacao Teste Linha ' || LEVEL,
           ROUND(DBMS_RANDOM.VALUE(10, 1500), 2),
           DATE '2023-01-01' + MOD(LEVEL, 1000)
      FROM dual
   CONNECT BY LEVEL <= c_qtd_linhas;
    COMMIT;

    v_tempo_set := (DBMS_UTILITY.GET_TIME - v_inicio) / 100.0;
    DBMS_OUTPUT.PUT_LINE('3. SQL Orientado a Conjuntos (Set-Based): ' || TO_CHAR(v_tempo_set, 'FM990.00') || ' segundos');

    -- -------------------------------------------------------------
    -- TABELA COMPARATIVA E CONCLUSÃO TÉCNICA
    -- -------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('--------------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('RESUMO COMPARATIVO DE PERFORMANCE:');
    DBMS_OUTPUT.PUT_LINE(' - SQL Orientado a Conjuntos foi ' || 
                         ROUND(v_tempo_loop / NULLIF(v_tempo_set, 0.001), 1) || 'x MAIS RÁPIDO que o Loop Linha a Linha.');
    DBMS_OUTPUT.PUT_LINE(' - SQL Orientado a Conjuntos foi ' || 
                         ROUND(v_tempo_bulk / NULLIF(v_tempo_set, 0.001), 1) || 'x MAIS RÁPIDO que o FORALL.');
    DBMS_OUTPUT.PUT_LINE('JUSTIFICATIVA ARQUITETURAL:');
    DBMS_OUTPUT.PUT_LINE(' O processamento Set-Based elimina o context switching entre a PL/SQL Engine');
    DBMS_OUTPUT.PUT_LINE(' e a SQL Engine e aproveita a escrita direta do Otimizador Oracle (Direct-Path Insert).');
    DBMS_OUTPUT.PUT_LINE('====================================================================');
END;
/

-- Limpeza
DROP TABLE t_benchmark_teste PURGE;
