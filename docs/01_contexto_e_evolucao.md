# 01. Contexto do Projeto e Evolução Arquitetural

## 1. Visão Geral e Desafio de Negócio
Este projeto tem como origem um sistema pessoal de controle e análise de despesas domésticas acumuladas ao longo de aproximadamente 5 anos de transações financeiras reais. 

Na sua versão inicial (V1), o fluxo de dados apoiava-se inteiramente em scripts Python com Pandas para tratamento e limpeza, SQLite como banco relacional embarcado e Power BI para visualização. Embora funcional para análises exploratórias pontuais, a arquitetura original apresentava limitações severas de escalabilidade, falta de governança, ausência de auditoria e fragilidade na integridade dos dados.

A presente versão (V2) reconstrói integralmente a solução sob os padrões corporativos de **Engenharia de Dados**, centralizando 100% da inteligência de transformação, governança e modelagem dimensional diretamente no **Oracle Database 23ai** através de **SQL avançado e PL/SQL**, utilizando boas práticas de desenvolvimento orientado a conjuntos.

---

## 2. Comparativo Detalhado: Arquitetura Legada (V1) × Arquitetura Enterprise (V2)

| Dimensão Técnica | Versão Legada (V1 - Python & SQLite) | Versão Enterprise (V2 - Oracle SQL & PL/SQL) | Ganho Arquitetural |
| :--- | :--- | :--- | :--- |
| **Motor de Processamento** | Python + Pandas em memória na máquina cliente | Oracle Database 23ai Enterprise / Free Engine | Processamento in-database com otimizador de custos (CBO). |
| **Estratégia de Ingestão** | `pd.read_csv()` frágil a quebras de linha e separadores | **External Table (`ORACLE_LOADER`)** com leitura agnóstica de linhas físicas | Resiliência total a formatos corrompidos e zero dependência de clientes locais. |
| **Camada RAW** | Inexistente (dados brutos descartados após leitura) | **`RAW_ORCAMENTO_LINHA`** append-only com hash SHA-256 e auditoria | Rastreabilidade histórica e possibilidade de reprocessamento sem a fonte externa. |
| **Tratamento de Inconsistências** | Descarte silencioso (`dropna`) e valores nulos forçados a zero (`fillna(0)`) | **`STG_REJEICAO`** detalhada com código do defeito, severidade e linha bruta | Zero perda de informação e auditoria completa de rejeições. |
| **Recomposição de Quebras** | Falhava ou corrompia 49 registros com descrição multilinhas | **Window Functions (`SUM() OVER` + `LISTAGG`)** em SQL orientado a conjuntos | Reconstituição precisa por conjuntos sem cursores lentos. |
| **Qualidade de Dados (DQ)** | Consultas avulsas pós-carga sem poder de bloqueio | **Motor dinâmico de Quality Gates (`PKG_DQ`)** com catalogue em banco | Barramento automático de cargas no DW em caso de falha crítica (`ORA-20050`). |
| **Estratégia de Carga** | Carga full destrutiva (`to_sql(if_exists='replace')`) | **`MERGE` incremental e idempotente** por chave de negócio e hash | Cargas estáveis, sem duplicação e com histórico preservado. |
| **Surrogate Keys (SK)** | Recriadas aleatoriamente a cada execução via `range()` | **`IDENTITY` no Oracle**, estáveis e perenes | Histórico contínuo entre cargas e consistência temporal. |
| **Modelagem de Dados** | Modelo relacional simples sem constraints ou integridade | **Star Schema (Fato e Dimensões)** com membro `-1` e FKs indexadas | Otimização para BI, sem locks de tabela e integridade referencial estrita. |
| **Auditoria e Observabilidade** | Nenhuma (apenas prints no terminal) | **Camada `CTL` completa com `PRAGMA AUTONOMOUS_TRANSACTION`** | Logs que sobrevivem a `ROLLBACK`, rastreamento de lote e etapas com métricas. |
| **Segurança e Acesso** | Arquivo SQLite único compartilhado | **RBAC (Role-Based Access Control)**: `ORC_OWNER` (dono) e `ORC_BI` (read-only) | Princípio do menor privilégio aplicado à camada de consumo. |

---

## 3. Principais Desafios Reais Solucionados

1. **Registros Quebrados por Quebra de Linha Embutida:**  
   No extrato original, transações com descrições longas continham caracteres `\r\n` internos, fazendo com que o Pandas interpretasse a continuação como uma nova linha com colunas desalinhadas. Na V2, a External Table ingere a linha física inteira (`ds_linha VARCHAR2(4000)`), e a package `PKG_STAGING` agrupa e recompõe os blocos em SQL puro utilizando `SUM(CASE WHEN REGEXP_LIKE(ds_linha, '^\d+;') THEN 1 ELSE 0 END) OVER (ORDER BY nr_linha)`.

2. **Distorção Estatística de Outliers:**  
   Em lotes pequenos, um valor extremo puxa a média para cima, mascarando o próprio outlier. Implementou-se a média Jackknife / Leave-One-Out, excluindo a própria transação da base de cálculo.

3. **Garantia de Não-Interrupção de Auditoria:**  
   Em pipelines tradicionais, quando uma etapa falha e sofre `ROLLBACK`, o log do erro também seria descartado. Com `PRAGMA AUTONOMOUS_TRANSACTION` na package `PKG_LOG`, a auditoria é confirmada em transação independente, mantendo o histórico de falhas e o stack trace com `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE`.
