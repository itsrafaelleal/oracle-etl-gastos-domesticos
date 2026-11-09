CREATE OR REPLACE PACKAGE pkg_dw AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_DW (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Carga da modelagem dimensional (Star Schema) via MERGE:
                 reclassificações, dimensões (SCD1) e fato incremental
                 com garantia de idempotência e integridade referencial.
       ===================================================================== */

    /**
     * Executa a carga do Data Warehouse para o lote especificado:
     * 1. Aplica regras de reclassificação automática.
     * 2. Realiza MERGE em DIM_RESPONSAVEL.
     * 3. Realiza MERGE em DIM_CLASSIFICACAO (SCD Tipo 1).
     * 4. Realiza MERGE idempotente em FATO_MOVIMENTACAO.
     */
    PROCEDURE carregar_dw(
        p_id_lote IN NUMBER
    );

    PROCEDURE carregar_dw(
        p_id_lote        IN NUMBER,
        p_qt_carregados  OUT NUMBER
    );

END pkg_dw;
/
