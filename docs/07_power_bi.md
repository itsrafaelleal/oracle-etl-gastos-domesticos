# 07. Integração com o Power BI e Modelo Semântico

## 1. Conexão com o Oracle Database
O Power BI conecta-se diretamente ao Oracle Database 23ai utilizando o **conector nativo Oracle**, consumindo unicamente as views semânticas expostas na camada `ORC_OWNER`:

- **Servidor:** `localhost:1521/FREEPDB1` (ou IP do servidor Homelab)
- **Modo de Conectividade:** `Import` (ou `DirectQuery` se exigido para tempo real)
- **Autenticação:** Usuário do Banco de Dados
- **Credenciais:**
  - Usuário: `ORC_BI`
  - Senha: `${ORC_BI_PASSWORD}` (definida no `.env`)

---

## 2. Modelo de Dados Dimensional (Star Schema)

No Power BI Desktop, o diagrama de relacionamentos deve ser configurado como **Star Schema puro**, com cardinalidade **1:N (Um para Muitos)** e **Filtro Cruzado Unidirecional** (da dimensão para a fato):

```
 ┌──────────────────────┐
 │ VW_BI_DIM_CALENDARIO │
 │ (sk_data)            │
 └──────────┬───────────┘
            │
            │ 1:N (Ativo: sk_data_competencia)
            │ 1:N (Inativo: sk_data_transacao)
            ▼
 ┌───────────────────────────┐      1:N      ┌─────────────────────────┐
 │ VW_BI_FATO_MOVIMENTACOES  │◄──────────────┤ VW_BI_DIM_CLASSIFICACAO │
 │                           │               │ (sk_classificacao)      │
 └──────────▲────────────────┘               └─────────────────────────┘
            │
            │ 1:N
            │
 ┌──────────┴───────────┐
 │ VW_BI_DIM_RESPONSAVEL│
 │ (sk_responsavel)     │
 └──────────────────────┘
```

---

## 3. Diretrizes de Modelagem no Power BI
1. **Zero Transformações no Power Query:**  
   Todo o parsing, tratamento de quebras de linha, padronização de tipos e segregação de inconsistências foi executado no Oracle. O Power Query deve atuar unicamente como leitor das views `VW_BI_*`.
2. **Role-Playing Dimension (Inteligência Temporal):**  
   - O relacionamento padrão e ativo liga `vw_bi_dim_calendario[sk_data]` a `vw_bi_fato_movimentacoes[sk_data_competencia]` (visão contábil e orçamentária).
   - O relacionamento secundário inativo liga a `vw_bi_fato_movimentacoes[sk_data_transacao]`. Quando o usuário desejar analisar os gastos pela data física da compra (comportamento de consumo), utiliza-se a medida DAX:
     ```dax
     [Gasto por Data da Compra] = 
     CALCULATE(
         [Total Gasto],
         USERELATIONSHIP(vw_bi_fato_movimentacoes[sk_data_transacao], vw_bi_dim_calendario[sk_data])
     )
     ```

3. **Catálogo de Medidas DAX Padronizadas:**  
   O arquivo [`dax_measures.dax`](file:///home/rafa/homelab/workspace/etl-dados-orcamento-oracle-powerbi/oracle-etl-gastos-domesticos/powerbi/dax_measures.dax) contém todas as métricas pré-calculadas recomendadas:
   - `[Total Gasto]`
   - `[Ticket Medio]`
   - `[Gasto Mes Anterior]`
   - `[Variacao MoM %]`
   - `[Variacao YoY %]`
   - `[Media Movel 3 Meses]`
   - `[% Participacao no Total]`
