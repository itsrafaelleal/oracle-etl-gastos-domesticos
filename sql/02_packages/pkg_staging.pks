CREATE OR REPLACE PACKAGE pkg_staging AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_STAGING (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Processamento e padronização da camada de Staging:
                 recomposição de registros multipartes via Window Functions,
                 parse por conjuntos, tipagem segura e segregação de rejeições.
       ===================================================================== */

    /**
     * Processa os dados brutos de um lote específico (RAW -> STAGING).
     * Recompõe linhas quebradas, valida tipos e segrega rejeições.
     */
    PROCEDURE processar_lote(
        p_id_lote IN NUMBER
    );

    PROCEDURE processar_lote(
        p_id_lote         IN NUMBER,
        p_qt_validos      OUT NUMBER,
        p_qt_rejeitados   OUT NUMBER
    );

END pkg_staging;
/
