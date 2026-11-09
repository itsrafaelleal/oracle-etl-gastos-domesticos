# 06. Performance, Planos de Execução e Benchmarks

## 1. Princípios de Otimização e Tuning
O pipeline foi construído adotando as diretrizes clássicas de alta performance para Oracle Database:
1. **Priorização de SQL Orientado a Conjuntos:** Eliminação de processamentos linha a linha (*slow-by-slow*) que geram overhead excessivo de chaveamento de contexto (*context switching*).
2. **Eliminação de Table Locks em Cascata:** Indexação mandatória de todas as Foreign Keys na tabela `FATO_MOVIMENTACAO`.
3. **Coleta Periódica de Estatísticas (`DBMS_STATS`):** Garantia de que o Otimizador Baseado em Custo (CBO) possua dados estatísticos reais para escolher os melhores planos de execução.

---

## 2. Benchmark Empírico: Comparativo de Estratégias

O script [`01_benchmark_set_bulk_loop.sql`](file:///home/rafa/homelab/workspace/etl-dados-orcamento-oracle-powerbi/oracle-etl-gastos-domesticos/sql/06_performance/01_benchmark_set_bulk_loop.sql) executou uma carga de **50.000 registros sintéticos** no Oracle 23ai sob três abordagens técnicas distintas:

| Abordagem | Mecanismo | Tempo de Execução | Fator de Ganho |
| :--- | :--- | :--- | :--- |
| **1. Loop Linha a Linha (Slow-by-Slow)** | Cursor explícito com `INSERT` unitário em cada iteração | **0.56 s** | Linha de Base (1.0x) |
| **2. PL/SQL BULK COLLECT + FORALL** | Processamento em lotes com array em memória (`LIMIT 1000`) | **0.14 s** | **4.0x mais rápido** que o Loop |
| **3. SQL Orientado a Conjuntos (Set-Based)** | `INSERT /*+ APPEND */ INTO ... SELECT ...` direto | **0.27 s** | **2.1x mais rápido** que o Loop |

### Análise dos Resultados:
- O processamento **linha a linha** é comprovadamente o mais lento devido à troca contínua entre a PL/SQL Engine e a SQL Engine a cada iteração.
- Embora `BULK COLLECT` reduza significativamente os *context switches*, o **SQL Orientado a Conjuntos** foi a escolha arquitetural adotada no pipeline porque realiza a transformação inteira dentro do motor SQL puro, dispensando alocação de coleções em memória na PGA (*Program Global Area*).

---

## 3. Análise de Planos de Execução (`EXPLAIN PLAN` e `DBMS_XPLAN`)

### 3.1 Consulta Dimensional no Star Schema
Ao executar a consulta analítica com agregação anual e junção das 3 dimensões, o otimizador CBO gerou o seguinte plano adaptativo:

```
---------------------------------------------------------------------------------------------------
| Id  | Operation                     | Name              | Rows  | Bytes | Cost (%CPU)| Time     |
---------------------------------------------------------------------------------------------------
|   0 | SELECT STATEMENT              |                   |     3 |   657 |    14  (15)| 00:00:01 |
|   1 |  HASH GROUP BY                |                   |     3 |   657 |    14  (15)| 00:00:01 |
|   2 |   NESTED LOOPS                |                   |     3 |   657 |    13   (8)| 00:00:01 |
|   3 |    NESTED LOOPS               |                   |     3 |   657 |    13   (8)| 00:00:01 |
|   4 |     VIEW                      | VW_GBC_17         |     3 |   564 |    10  (10)| 00:00:01 |
|   5 |      HASH GROUP BY            |                   |     3 |   597 |    10  (10)| 00:00:01 |
|*  6 |       HASH JOIN               |                   |   147 | 29253 |     9   (0)| 00:00:01 |
|   7 |        TABLE ACCESS FULL      | DIM_CLASSIFICACAO |    23 |  2691 |     3   (0)| 00:00:01 |
|*  8 |        HASH JOIN              |                   |   147 | 12054 |     6   (0)| 00:00:01 |
|   9 |         TABLE ACCESS FULL     | DIM_RESPONSAVEL   |     3 |   195 |     3   (0)| 00:00:01 |
|  10 |         TABLE ACCESS FULL     | FATO_MOVIMENTACAO |   147 |  2499 |     3   (0)| 00:00:01 |
|* 11 |     INDEX UNIQUE SCAN         | PK_DIM_CALENDARIO |     1 |       |     0   (0)| 00:00:01 |
|* 12 |    TABLE ACCESS BY INDEX ROWID| DIM_CALENDARIO    |     1 |    31 |     1   (0)| 00:00:01 |
---------------------------------------------------------------------------------------------------
```

**Destaques do Plano:**
- O otimizador utiliza **`HASH JOIN`** eficiente para cruzar a tabela fato com as dimensões de baixa cardinalidade (`DIM_RESPONSAVEL` e `DIM_CLASSIFICACAO`), mantendo as tabelas menores na tabela hash em memória.
- Acesso à `DIM_CALENDARIO` realizado via **`INDEX UNIQUE SCAN`** na Primary Key `PK_DIM_CALENDARIO`, com custo de leitura zerado (`Cost 0`).

---

## 4. Por que NÃO particionar esta tabela fato?
- O volume anual do projeto de gastos pessoais é de aproximadamente **700 a 800 transações/ano** (~4.000 linhas em 5 anos).
- Em tabelas com menos de alguns milhões de registros, o particionamento gera *overhead* desnecessário de dicionário de dados e manutenção de índices globais.
- A documentação reconhece tecnicamente que o particionamento mensal por intervalo (`PARTITION BY RANGE (sk_data_competencia) INTERVAL (NUMTOYMINTERVAL(1, 'MONTH'))`) seria justificável caso o sistema migrasse para um cenário corporativo com dezenas de milhões de transações e necessidade de *Partition Exchange* na carga.
