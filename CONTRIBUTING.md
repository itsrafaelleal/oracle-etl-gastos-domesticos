# Guia de Contribuicao

Obrigado pelo interesse em contribuir! Este documento descreve o fluxo de
trabalho adotado no projeto. Ele existe tanto para colaboradores externos
quanto para manter consistencia no desenvolvimento do dia a dia.

## Fluxo de trabalho: branch -> PR -> merge

Nada e commitado direto na `main`. Toda mudanca passa por um Pull Request,
mesmo que pequena. Esse e o fluxo esperado de um ambiente profissional de
engenharia de dados e mantem o historico limpo e revisavel.

1. **Crie uma branch** a partir da `main`, com prefixo por tipo:
   - `feat/...`   nova funcionalidade (ex.: `feat/dim-forma-pagamento`)
   - `fix/...`    correcao de bug
   - `docs/...`   documentacao
   - `chore/...`  tarefas de infraestrutura/configuracao
   - `ci/...`     mudancas no pipeline de CI

   ```bash
   git checkout main
   git pull --ff-only
   git checkout -b feat/minha-mudanca
   ```

2. **Faca commits pequenos e descritivos.** Use mensagens no imperativo e
   explique o *porque* no corpo quando a mudanca nao for obvia. O projeto
   segue o estilo de [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `docs:`, `chore:`, `ci:`).

3. **Abra o Pull Request** para a `main`. O
   [template de PR](.github/pull_request_template.md) ja traz o checklist a
   ser preenchido.

4. **Garanta o CI verde** antes do merge (veja abaixo).

5. **Merge** apos a revisao (ou diretamente, quando trabalhando sozinho no
   seu proprio fork/repo).

## Regras de seguranca (inegociaveis)

Este projeto lida com dados financeiros. As seguintes regras sao validadas
automaticamente pelo CI (`.github/workflows/ci.yml`) e **nunca** devem ser
burladas:

- **Nenhum dado financeiro real** entra no repositorio. Apenas o dataset
  sintetico em `data/sample/` e versionado. Todo `*.csv`, `*.xlsx`, `*.pbix`,
  `*.dmp` etc. fora de `data/sample/` e bloqueado.
- **Nenhum segredo** e versionado. O `.env` fica fora do controle de versao;
  use `.env.example` como modelo (apenas placeholders).

## Rodando as validacoes localmente

Antes de abrir o PR, voce pode reproduzir os checks do CI:

```bash
# 1. Guarda: nenhum dado real versionado (fora de data/sample/)
git ls-files '*.csv' '*.xlsx' '*.xls' '*.db' '*.sqlite' '*.dmp' '*.pbix' \
  | grep -v '^data/sample/' && echo "FALHA: dado real versionado" || echo "OK"

# 2. Guarda: .env nao versionado
git ls-files --error-unmatch .env 2>/dev/null && echo "FALHA: .env versionado" || echo "OK"

# 3. Smoke test do gerador de dados sinteticos
python -m py_compile tools/gerador_dados_sinteticos/gerar_dataset.py && echo "OK"
```

## Rodando o pipeline completo

Consulte o [README](README.md) para os pre-requisitos. Em resumo:

```bash
make up            # sobe o container Oracle 23ai Free
make wait-healthy  # aguarda o banco ficar saudavel
make setup         # cria schemas, diretorios e grants (SYSTEM)
make dataset       # gera o dataset sintetico
make install       # instala DDL, packages, seeds e views
make test-all      # roda a suite de testes ponta a ponta
make pipeline      # processa um lote pelo pipeline orquestrado
```

## Reportando problemas

Use os [templates de issue](.github/ISSUE_TEMPLATE/) para reportar bugs ou
sugerir melhorias. Inclua mensagens de erro (ex.: `ORA-xxxxx`) e o conteudo
relevante da tabela de auditoria `CTL_LOG` quando aplicavel.
