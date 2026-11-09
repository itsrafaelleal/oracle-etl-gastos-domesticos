CREATE OR REPLACE PACKAGE pkg_dq AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_DQ (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Motor de Qualidade de Dados (Data Quality Gates):
                 avalia dinamicamente o catálogo CTL_DQ_REGRA sobre a Staging,
                 registra em CTL_DQ_RESULTADO e barra a continuidade se houver
                 violação de regra BLOQUEANTE.
       ===================================================================== */

    -- Exceção customizada disparada quando regras bloqueantes falham
    e_quality_gate_failed EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_quality_gate_failed, -20050);

    /**
     * Executa todas as regras ativas de DQ para o lote informado.
     * Caso alguma regra BLOQUEANTE falhe, grava os resultados e lança ORA-20050.
     */
    PROCEDURE executar_regras(
        p_id_lote IN NUMBER
    );

    PROCEDURE executar_regras(
        p_id_lote          IN NUMBER,
        p_fl_bloqueado     OUT CHAR,
        p_qt_falhas_bloq   OUT NUMBER,
        p_qt_alertas       OUT NUMBER
    );

END pkg_dq;
/
