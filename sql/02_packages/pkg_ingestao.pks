CREATE OR REPLACE PACKAGE pkg_ingestao AS
    /* =====================================================================
       PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
       OBJETO:  PKG_INGESTAO (Especificação)
       SCHEMA:  ORC_OWNER
       OBJETIVO: Ingestão de arquivos CSV para a camada RAW através de
                 External Tables com SQL dinâmico e rastreabilidade total.
       ===================================================================== */

    /**
     * Orquestra a ingestão de um arquivo CSV específico localizado no Inbox:
     * 1. Inicia o lote em CTL_LOTE.
     * 2. Ajusta o LOCATION da External Table EXT_ORCAMENTO via SQL dinâmico.
     * 3. Carrega linha a linha física para RAW_ORCAMENTO_LINHA com hash SHA-256.
     * 4. Registra métricas e encerra a etapa.
     * Retorna o ID do lote criado.
     */
    FUNCTION carregar_arquivo(
        p_nm_arquivo IN VARCHAR2
    ) RETURN NUMBER;

    PROCEDURE carregar_arquivo(
        p_nm_arquivo IN VARCHAR2,
        p_id_lote    OUT NUMBER
    );

END pkg_ingestao;
/
