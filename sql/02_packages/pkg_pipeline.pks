CREATE OR REPLACE PACKAGE pkg_pipeline AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_PIPELINE (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Orquestrador mestre do pipeline ETL:
                 Ingestão -> Staging -> Data Quality Gates -> Carga DW ->
                 Estatísticas DBMS_STATS -> Fechamento de Lote.
       ===================================================================== */

    -- Exceções customizadas
    e_concorrencia_ativa EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_concorrencia_ativa, -20060);

    /**
     * Orquestra o fluxo completo ponta a ponta para um arquivo do Inbox.
     * Retorna o ID do lote processado.
     */
    PROCEDURE executar_carga_arquivo(
        p_nm_arquivo IN VARCHAR2,
        p_id_lote    OUT NUMBER
    );

    FUNCTION executar_carga_arquivo(
        p_nm_arquivo IN VARCHAR2
    ) RETURN NUMBER;

    /**
     * Reprocessa um lote a partir da camada RAW já persistida,
     * sem necessidade de reler o arquivo original no inbox.
     */
    PROCEDURE reprocessar_lote(
        p_id_lote IN NUMBER
    );

END pkg_pipeline;
/
