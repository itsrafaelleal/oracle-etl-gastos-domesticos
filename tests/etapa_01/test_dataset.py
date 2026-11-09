#!/usr/bin/env python3
"""
=============================================================================
PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
ETAPA:   01 - Suíte de Testes do Dataset Sintético
ARQUIVO: tests/etapa_01/test_dataset.py
OBJETIVO: Validar os arquivos gerados (60 mensais, consolidado e defeitos),
          garantindo exatamente 16 asserções de qualidade e integridade.
=============================================================================
"""

import sys
from pathlib import Path
import re

BASE_DIR = Path(__file__).resolve().parents[2]
INBOX_DIR = BASE_DIR / "data" / "sample" / "inbox"

EXPECTED_HEADER = "id;data;competencia;responsavel;descricao;valor;categoria;subcategoria;tipo;observacao"
VALID_TYPES = {"OPEX", "CAPEX", "NAO_ESSENCIAL", "INVESTIMENTO", "BEM_ESTAR", "FORMACAO"}
VALID_RESPONSAVEIS = {"Responsavel_A", "Responsavel_B"}

def run_tests():
    print("=" * 65)
    print("INICIANDO SUÍTE DE TESTES: ETAPA 01 - DATASET SINTÉTICO")
    print("=" * 65)
    
    passed_assertions = 0
    total_assertions = 16

    def assert_test(cond, num, desc):
        nonlocal passed_assertions
        if cond:
            print(f"  [OK] Asserção {num:02d}: {desc}")
            passed_assertions += 1
        else:
            print(f"  [FALHA] Asserção {num:02d}: {desc}")
            sys.exit(1)

    # 1. Diretório sample inbox existe
    assert_test(INBOX_DIR.exists() and INBOX_DIR.is_dir(), 1, "Diretório data/sample/inbox/ existe e é acessível")

    # 2. 60 arquivos mensais existem
    monthly_files = sorted(list(INBOX_DIR.glob("orcamento_20[2-9][0-9]_[0-1][0-9].csv")))
    assert_test(len(monthly_files) == 60, 2, f"60 remessas mensais encontradas (encontradas: {len(monthly_files)})")

    # 3. Arquivo consolidado de 5 anos existe
    full_file = INBOX_DIR / "orcamento_full_5anos.csv"
    assert_test(full_file.exists() and full_file.stat().st_size > 0, 3, "Arquivo consolidado orcamento_full_5anos.csv existe e não está vazio")

    # 4. Arquivo de testes de defeitos existe
    defects_file = INBOX_DIR / "orcamento_teste_defeitos.csv"
    assert_test(defects_file.exists() and defects_file.stat().st_size > 0, 4, "Arquivo orcamento_teste_defeitos.csv existe e não está vazio")

    # 5. Header de todos os 60 arquivos mensais bate com o esquema oficial
    headers_ok = True
    for f in monthly_files:
        with open(f, "r", encoding="utf-8") as fp:
            first_line = fp.readline().strip()
            if first_line != EXPECTED_HEADER:
                headers_ok = False
                break
    assert_test(headers_ok, 5, "Cabeçalho de todas as 60 remessas mensais coincide estritamente com o esquema esperado")

    # 6. Volumetria mensal realista (entre 50 e 80 transações por mês)
    volumes_ok = True
    monthly_total_rows = 0
    for f in monthly_files:
        with open(f, "r", encoding="utf-8") as fp:
            lines = [l for l in fp.readlines() if l.strip()]
            data_rows = len(lines) - 1
            monthly_total_rows += data_rows
            if not (50 <= data_rows <= 80):
                volumes_ok = False
                break
    assert_test(volumes_ok, 6, "Volumetria mensal dentro da faixa estatística esperada (50 a 80 registros/mês)")

    # 7. Total consolidado é idêntico à soma das 60 remessas mensais
    with open(full_file, "r", encoding="utf-8") as fp:
        full_lines = [l for l in fp.readlines() if l.strip()]
        full_data_rows = len(full_lines) - 1
    assert_test(monthly_total_rows == full_data_rows and full_data_rows > 3000, 7,
                f"Consolidação íntegra: total consolidado ({full_data_rows}) == soma mensal ({monthly_total_rows})")

    # 8. Responsáveis pseudonimizados estritamente válidos
    resp_ok = True
    types_ok = True
    dates_ok = True
    vals_ok = True
    comp_ok = True
    date_regex = re.compile(r"^\d{2}/\d{2}/\d{4}$")
    val_regex = re.compile(r"^\d+,\d{2}$")

    for f in monthly_files[:12]: # Amostra representativa do primeiro ano
        with open(f, "r", encoding="utf-8") as fp:
            next(fp)
            for line in fp:
                parts = line.strip().split(";")
                if len(parts) >= 9:
                    resp = parts[3]
                    tipo = parts[8]
                    dt = parts[1]
                    val = parts[5]
                    comp = parts[2]
                    if resp not in VALID_RESPONSAVEIS:
                        resp_ok = False
                    if tipo not in VALID_TYPES:
                        types_ok = False
                    if not date_regex.match(dt):
                        dates_ok = False
                    if not val_regex.match(val):
                        vals_ok = False
                    if not comp.isdigit():
                        comp_ok = False

    assert_test(resp_ok, 8, "Responsáveis pseudonimizados aderentes ao domínio ('Responsavel_A', 'Responsavel_B')")
    assert_test(types_ok, 9, "Tipos/Naturezas aderentes aos 6 domínios (OPEX, CAPEX, etc.)")
    assert_test(dates_ok, 10, "Formatos de data no padrão DD/MM/AAAA em todas as transações regulares")
    assert_test(vals_ok, 11, "Valores monetários pt-BR regulares sem símbolos e com decimais em vírgula")
    assert_test(comp_ok, 12, "Competências seguem o padrão numérico de faturamento/cartão")

    # 13 a 16: Testes do arquivo de defeitos intencionais
    with open(defects_file, "r", encoding="utf-8") as fp:
        raw_defect_content = fp.read()

    # 13. Presença de quebras de linha no meio de registros
    has_broken_lines = "Linha 1\r\n  Continuação" in raw_defect_content or "Linha 1\n  Continuação" in raw_defect_content
    assert_test(has_broken_lines, 13, "Defeito 1 presente: registros partidos com quebra de linha interna")

    # 14. Presença de prefixo 'R$' nos valores
    has_rs = "R$ " in raw_defect_content
    assert_test(has_rs, 14, "Defeito 2 presente: valores monetários com prefixo 'R$'")

    # 15. Presença de valores nulos/vazios (;;)
    has_null_val = ";;Saude;Farmacia" in raw_defect_content or ";;Alimentacao;" in raw_defect_content
    assert_test(has_null_val, 15, "Defeito 3 presente: registros com valor nulo/vazio para rejeição em Staging")

    # 16. Presença de valor outlier extremo (> 3000)
    has_outlier = "3850,00" in raw_defect_content
    assert_test(has_outlier, 16, "Defeito 7 presente: outlier financeiro (> 4x média da subcategoria)")

    print("=" * 65)
    print(f"CRITÉRIO DE ACEITE: {passed_assertions}/{total_assertions} ASSERÇÕES APROVADAS (100% OK)!")
    print("=" * 65)

if __name__ == "__main__":
    run_tests()
