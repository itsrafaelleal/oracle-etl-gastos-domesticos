-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ARQUIVO: sql/install.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Script mestre de instalação completa do banco:
--           DDL -> Packages (PKS/PKB) -> Seeds -> Views BI.
-- =====================================================================

SET DEFINE OFF;
SET SQLBLANKLINES ON;
SET SERVEROUTPUT ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

PROMPT =====================================================================
PROMPT INICIANDO INSTALAÇÃO DO PIPELINE ETL (ORC_OWNER)
PROMPT =====================================================================

PROMPT 1. Criando tabelas da Camada CTL...
@@01_ddl/ctl/01_tabelas_ctl.sql;

PROMPT 2. Criando tabelas da Camada RAW e External Tables...
@@01_ddl/raw/01_raw_tabelas.sql;

PROMPT 3. Criando tabelas da Camada STAGING...
@@01_ddl/stg/01_stg_tabelas.sql;

PROMPT 4. Criando tabelas da Camada DW (Star Schema)...
@@01_ddl/dw/01_dw_tabelas.sql;

PROMPT 5. Compilando Package PKG_LOG...
@@02_packages/pkg_log.pks;
@@02_packages/pkg_log.pkb;

PROMPT 6. Compilando Package PKG_INGESTAO...
@@02_packages/pkg_ingestao.pks;
@@02_packages/pkg_ingestao.pkb;

PROMPT 7. Compilando Package PKG_STAGING...
@@02_packages/pkg_staging.pks;
@@02_packages/pkg_staging.pkb;

PROMPT 8. Compilando Package PKG_DQ...
@@02_packages/pkg_dq.pks;
@@02_packages/pkg_dq.pkb;

PROMPT 9. Compilando Package PKG_DW...
@@02_packages/pkg_dw.pks;
@@02_packages/pkg_dw.pkb;

PROMPT 10. Compilando Package PKG_PIPELINE...
@@02_packages/pkg_pipeline.pks;
@@02_packages/pkg_pipeline.pkb;

PROMPT 11. Carregando Seeds e Parâmetros CTL...
@@03_seed/01_seed_ctl.sql;

PROMPT 12. Carregando Seeds Dimensionais e Calendário DW...
@@03_seed/02_seed_dw.sql;

PROMPT 13. Criando Views Semânticas para o Power BI e Grants...
@@04_views_bi/01_views_bi.sql;

PROMPT =====================================================================
PROMPT INSTALAÇÃO CONCLUÍDA COM SUCESSO!
PROMPT =====================================================================
