# 05. Auditoria, Rastreabilidade e Observabilidade

## 1. Arquitetura de Controle (`CTL`)
A camada de controle foi concebida para fornecer observabilidade completa sobre todas as operações do pipeline, registrando métricas de tempo, volumetria, avisos e mensagens de erro com precisão forense.

```
┌─────────────────────────────────────────────────────────────┐
│                          CTL_LOTE                           │
│  (id_lote, nm_arquivo, hash_arquivo, status, inicio, fim,   │
│   qt_lidas, qt_validas, qt_rejeitadas, qt_carregadas, erro) │
└──────────────────────────────┬──────────────────────────────┘
                               │ 1:N
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                     CTL_EXECUCAO_ETAPA                      │
│  (id_execucao_etapa, id_lote, nm_etapa, status, inicio, fim,│
│   qt_processados, qt_rejeitados, mensagem)                  │
└─────────────────────────────────────────────────────────────┘
                               ▲
                               │ 1:N
┌──────────────────────────────┴──────────────────────────────┐
│                           CTL_LOG                           │
│  (id_log, id_lote, procedimento, nivel, mensagem, backtrace)│
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Decisão Arquitetural: Transações Autônomas (`PRAGMA AUTONOMOUS_TRANSACTION`)

### O Problema em Ambientes Tradicionais
Em sistemas de banco de dados convencionais, se uma package de processamento encontra um erro inesperado e aciona uma instrução `ROLLBACK` no bloco `EXCEPTION`, todos os `INSERTs` realizados na tabela de logs durante aquela transação são revertidos juntamente com os dados de negócio. Isso resulta na perda total das mensagens de erro e do rastreamento técnico da falha.

### A Solução Implementada
Na package `PKG_LOG`, todos os procedimentos de escrita de auditoria (`registrar_log`, `iniciar_lote`, `finalizar_lote`, `iniciar_etapa`, `finalizar_etapa`) utilizam a diretiva:
```sql
PRAGMA AUTONOMOUS_TRANSACTION;
```
Essa diretiva instrui o motor PL/SQL a suspender temporariamente a transação principal chamadora, abrir um escopo transacional independente, efetivar a gravação do log com `COMMIT` e retomar a execução normal.

Dessa forma, mesmo que a operação principal sofra um `ROLLBACK` total, **o registro do erro e as métricas parciais permanecem intactos na tabela `CTL_LOG`**, garantindo rastreabilidade absoluta para a equipe de suporte e engenharia.

---

## 3. Captura Detalhada de Erros (`DBMS_UTILITY`)
Para eliminar mensagens genéricas do tipo "Erro inesperado", as rotinas de tratamento de exceções utilizam:
- `SQLERRM`: Código e descrição formal do erro retornado pelo Oracle.
- `DBMS_UTILITY.FORMAT_ERROR_BACKTRACE`: Aponta a package e o número exato da linha do código-fonte onde a falha teve origem.
