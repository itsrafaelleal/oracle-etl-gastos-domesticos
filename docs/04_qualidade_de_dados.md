# 04. Qualidade de Dados e Quality Gates

## 1. Estratégia de Data Quality (DQ)
O pipeline adota uma abordagem de **defesa em profundidade**, implementando verificações em múltiplos níveis:
1. **Camada de Staging:** Validação estrutural de tipos e segregação física de anomalias em `STG_REJEICAO`.
2. **Quality Gates (`PKG_DQ`):** Validação por regras dinâmicas catalogadas antes de autorizar a escrita no Data Warehouse.

---

## 2. Catálogo Central de Regras (`CTL_DQ_REGRA`)

| Código da Regra | Nome / Descrição | Severidade | Ação em Caso de Violação | SQL de Validação |
| :--- | :--- | :--- | :--- | :--- |
| **`DQ_VALOR_NULO`** | Valor Financeiro Obrigatório | **BLOQUEANTE** | Interrompe o pipeline com `ORA-20050`. Lote marcado como `FAILED`. | `SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND vl_transacao IS NULL` |
| **`DQ_DATA_NULA`** | Data da Transação Obrigatória | **BLOQUEANTE** | Interrompe o pipeline com `ORA-20050`. Lote marcado como `FAILED`. | `SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND dt_transacao IS NULL` |
| **`DQ_DESCRICAO_NULA`** | Descrição da Despesa Obrigatória | **BLOQUEANTE** | Interrompe o pipeline com `ORA-20050`. Lote marcado como `FAILED`. | `SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND (ds_transacao IS NULL OR TRIM(ds_transacao) IS NULL)` |
| **`DQ_DUPLICIDADE_CHAVE`** | Detecção de Transações Duplicadas | **BLOQUEANTE** | Interrompe o pipeline com `ORA-20050`. Evita ingestão de dados duplicados acidentalmente no mesmo lote. | `SELECT COUNT(*) FROM (SELECT dt_transacao, nm_responsavel, ds_transacao, vl_transacao, COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote GROUP BY dt_transacao, nm_responsavel, ds_transacao, vl_transacao HAVING COUNT(*) > 1)` |
| **`DQ_OUTLIER_SUB`** | Alerta de Valor Muito Acima da Média | **ALERTA** | Não bloqueia a carga. Registra inconsistências em `CTL_DQ_RESULTADO` para auditoria e sinaliza `fl_outlier = 'S'` na fato. | `SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND fl_outlier = 'S'` |
| **`DQ_LAG_FATURA_EXCESSIVO`** | Alerta de Competência Temporal Deslocada | **ALERTA** | Não bloqueia a carga. Sinaliza transações com distância entre competência e data maior que 12 meses ou lag negativo. | `SELECT COUNT(*) FROM stg_orcamento WHERE id_lote = :p_id_lote AND fl_lag_suspeito = 'S'` |

---

## 3. Funcionamento do Motor `PKG_DQ`

A execução das regras ocorre através de **SQL Dinâmico** associado a um cursor explícito de metadados:
1. O cursor `c_regras` recupera todas as regras ativas (`fl_ativo = 'S'`) em `CTL_DQ_REGRA`.
2. Para cada regra, executa-se dinamicamente a consulta passando o identificador do lote atual (`:p_id_lote`).
3. O resultado numérico de inconsistências é armazenado na tabela de histórico `CTL_DQ_RESULTADO` com status `APROVADO`, `REPROVADO` ou `ALERTA`.
4. Se a contagem de falhas bloqueantes (`p_qt_falhas_bloq`) for maior que zero:
   - A etapa `DATA_QUALITY_GATE` é finalizada com status `FAILED`.
   - Dispara-se a exceção customizada `e_quality_gate_failed` (`RAISE_APPLICATION_ERROR(-20050, ...)`), garantindo que nenhuma alteração seja promovida ao Data Warehouse.
