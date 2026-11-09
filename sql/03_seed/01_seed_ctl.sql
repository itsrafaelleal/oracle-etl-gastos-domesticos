-- =====================================================================
-- PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
-- ETAPA:   02 - Camada de Controle e Auditoria (CTL)
-- ARQUIVO: sql/03_seed/01_seed_ctl.sql
-- SCHEMA:  ORC_OWNER
-- OBJETIVO: Carga inicial de parâmetros e catálogo de regras de DQ.
-- =====================================================================

SET SQLBLANKLINES ON;
WHENEVER SQLERROR EXIT FAILURE ROLLBACK;

-- 1. PARÂMETROS OPERACIONAIS
MERGE INTO cfg_parametro dest
USING (
    SELECT 'DELIMITADOR_CSV' AS cd, ';' AS vl, 'Delimitador padrão do arquivo CSV' AS ds FROM dual UNION ALL
    SELECT 'ENCODING_ARQUIVO' AS cd, 'UTF8' AS vl, 'Conjunto de caracteres esperado no CSV' AS ds FROM dual UNION ALL
    SELECT 'DIRETORIO_INBOX' AS cd, 'DIR_ORC_INBOX' AS vl, 'Objeto DIRECTORY Oracle para arquivos de entrada' AS ds FROM dual UNION ALL
    SELECT 'MAX_DIAS_FUTURO' AS cd, '30' AS vl, 'Tolerância em dias para transações futuras' AS ds FROM dual UNION ALL
    SELECT 'ANO_MINIMO' AS cd, '2020' AS vl, 'Ano mínimo aceitável para compras válidas' AS ds FROM dual UNION ALL
    SELECT 'FATOR_OUTLIER' AS cd, '4.0' AS vl, 'Multiplicador da média para sinalizar outliers' AS ds FROM dual
) src
ON (dest.cd_parametro = src.cd)
WHEN MATCHED THEN
    UPDATE SET dest.vl_parametro = src.vl, dest.ds_parametro = src.ds, dest.dt_atualizacao = SYSDATE
WHEN NOT MATCHED THEN
    INSERT (cd_parametro, vl_parametro, ds_parametro, dt_atualizacao)
    VALUES (src.cd, src.vl, src.ds, SYSDATE);

-- 2. REGRAS INICIAIS DO CATÁLOGO DE DATA QUALITY (DQ)
MERGE INTO ctl_dq_regra dest
USING (
    SELECT 'DQ_VALOR_NULO' AS cd,
           'Valor Financeiro Obrigatório' AS nm,
           'Garante que nenhum registro ingresse sem valor financeiro definido.' AS ds,
           'BLOQUEANTE' AS sev,
           'SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND vl_transacao IS NULL' AS qry,
           'S' AS atv FROM dual UNION ALL
    SELECT 'DQ_DATA_NULA' AS cd,
           'Data da Transação Obrigatória' AS nm,
           'Garante que nenhuma transação ingresse com data vazia ou corrompida.' AS ds,
           'BLOQUEANTE' AS sev,
           'SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND dt_transacao IS NULL' AS qry,
           'S' AS atv FROM dual UNION ALL
    SELECT 'DQ_DESCRICAO_NULA' AS cd,
           'Descrição da Despesa Obrigatória' AS nm,
           'Garante que não haja lançamentos sem texto de identificação/descrição.' AS ds,
           'BLOQUEANTE' AS sev,
           'SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND (ds_transacao IS NULL OR TRIM(ds_transacao) IS NULL)' AS qry,
           'S' AS atv FROM dual UNION ALL
    SELECT 'DQ_DUPLICIDADE_CHAVE' AS cd,
           'Detecção de Linhas Duplicadas no Mesmo Lote' AS nm,
           'Identifica se o arquivo contém transações idênticas (mesma data, responsável, valor e descrição).' AS ds,
           'BLOQUEANTE' AS sev,
           'SELECT COUNT(*) FROM (SELECT dt_transacao, nm_responsavel, ds_transacao, vl_transacao, COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote GROUP BY dt_transacao, nm_responsavel, ds_transacao, vl_transacao HAVING COUNT(*) > 1)' AS qry,
           'S' AS atv FROM dual UNION ALL
    SELECT 'DQ_OUTLIER_SUB' AS cd,
           'Alerta de Valor Muito Acima da Média' AS nm,
           'Sinaliza valores que ultrapassam 4 vezes a média histórica da respectiva subcategoria.' AS ds,
           'ALERTA' AS sev,
           'SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND fl_outlier = ''S''' AS qry,
           'S' AS atv FROM dual UNION ALL
    SELECT 'DQ_LAG_FATURA_EXCESSIVO' AS cd,
           'Alerta de Competência Temporal Deslocada' AS nm,
           'Sinaliza transações com distância entre competência e data maior que 12 meses.' AS ds,
           'ALERTA' AS sev,
           'SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND fl_lag_suspeito = ''S''' AS qry,
           'S' AS atv FROM dual
) src
ON (dest.cd_regra = src.cd)
WHEN MATCHED THEN
    UPDATE SET dest.nm_regra = src.nm, dest.ds_regra = src.ds,
               dest.tp_severidade = src.sev, dest.ds_sql_validacao = src.qry, dest.fl_ativo = src.atv
WHEN NOT MATCHED THEN
    INSERT (cd_regra, nm_regra, ds_regra, tp_severidade, ds_sql_validacao, fl_ativo, dt_criacao)
    VALUES (src.cd, src.nm, src.ds, src.sev, src.qry, src.atv, SYSDATE);

COMMIT;
