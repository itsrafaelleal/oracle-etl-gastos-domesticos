#!/usr/bin/env python3
"""
=============================================================================
PROJETO: Pipeline ETL Gastos Domésticos (Oracle SQL e PL/SQL)
ETAPA:   01 - Geração de Dataset Sintético
ARQUIVO: tools/gerador_dados_sinteticos/gerar_dataset.py
OBJETIVO: Gerar 5 anos (60 meses) de dados sintéticos realistas, mantendo
          distribuições estatísticas de gastos domésticos e criando arquivos
          mensais, consolidados e um lote específico com defeitos propositais.
=============================================================================
"""

import os
import random
from datetime import date, timedelta
from pathlib import Path

# Fixar seed para reprodutibilidade estrita
RANDOM_SEED = 42
random.seed(RANDOM_SEED)

BASE_DIR = Path(__file__).resolve().parents[2]
INBOX_DIR = BASE_DIR / "data" / "sample" / "inbox"
DATA_INBOX_DIR = BASE_DIR / "data" / "inbox"

# 1. Definições de Domínio e Taxonomia
RESPONSAVEIS = ["Responsavel_A", "Responsavel_B"]

TAXONOMIA = [
    # Categoria, Subcategoria, Tipo, (min_val, max_val), peso_frequencia, descricoes_exemplo
    ("Alimentacao", "Mercado", "OPEX", (80.0, 650.0), 20, [
        "Supermercado Big Bom", "Hipermercado Zaffari", "Mercado Central", "Atacadao Maxxi", "Hortifruti Fresco"
    ]),
    ("Alimentacao", "Restaurante_Delivery", "NAO_ESSENCIAL", (35.0, 220.0), 14, [
        "Ifood Burguer", "Pizzaria Bella", "Restaurante Sabor Caseiro", "Sushi Express", "Padaria Estrela"
    ]),
    ("Alimentacao", "Cafeteria", "NAO_ESSENCIAL", (15.0, 60.0), 6, [
        "Cafeteria Grao Nobre", "Starbucks Centro", "Cafe & Cia", "Boutique do Cafe"
    ]),
    ("Moradia", "Aluguel", "OPEX", (1200.0, 1800.0), 2, [
        "Aluguel Apartamento", "Locacao Mensal Residencia"
    ]),
    ("Moradia", "Condominio", "OPEX", (350.0, 600.0), 2, [
        "Condominio Edificio Solar", "Taxa Condominial Mensal"
    ]),
    ("Moradia", "Luz", "OPEX", (120.0, 320.0), 2, [
        "Conta de Energia Eletrica", "Celesc Energia", "Fatura Luz Mensal"
    ]),
    ("Moradia", "Internet", "OPEX", (99.0, 150.0), 2, [
        "Fibra Optica 500MB", "Internet Banda Larga Claro", "Provedor ConectMax"
    ]),
    ("Moradia", "Faxina", "OPEX", (150.0, 250.0), 4, [
        "Diarista Faxina Quinzenal", "Servico Limpeza Residencial"
    ]),
    ("Moradia", "Manutencao_Reparos", "OPEX", (40.0, 450.0), 3, [
        "Ferragem Central", "Material Hidraulico Torneira", "Lampadas LED Leroy", "Reparo Fechadura"
    ]),
    ("Moradia", "Moveis_Eletros", "CAPEX", (180.0, 1200.0), 3, [
        "Sofa 6/12", "Cama Box 3/10", "Geladeira Inox Parc. 4/10", "Aspirador Robo", "Mesa Escritorio"
    ]),
    ("Transporte", "Gasolina", "OPEX", (80.0, 280.0), 12, [
        "Posto Ipiranga Centro", "Posto Shell Combustiveis", "Posto Petrobras BR", "Abastecimento Viagem"
    ]),
    ("Transporte", "Pedagio", "OPEX", (8.5, 45.0), 5, [
        "Sem Parar Pedagio", "ConectCar Rodovia", "Pedagio CCR ViaCosteira"
    ]),
    ("Transporte", "Aplicativo", "NAO_ESSENCIAL", (18.0, 65.0), 8, [
        "Uber Corrida", "99App Viagem Urbana", "Uber Mercado"
    ]),
    ("Transporte", "Manutencao_Veiculo", "CAPEX", (150.0, 950.0), 2, [
        "Troca de Oleo e Filtros", "Revisao Freios AutoCenter", "Geometria e Balanceamento", "Pneu Aro 16"
    ]),
    ("Saude", "Farmacia", "BEM_ESTAR", (25.0, 220.0), 8, [
        "Farmacia Raia", "Drogaria Sao Paulo", "Panvel Medicamentos", "Vitaminas e Suplementos"
    ]),
    ("Saude", "Consultas_Exames", "BEM_ESTAR", (120.0, 450.0), 2, [
        "Consulta Odontologica", "Exame de Sangue Laboratorio", "Fisioterapia Sessao"
    ]),
    ("Lazer", "Assinaturas", "NAO_ESSENCIAL", (19.9, 65.0), 5, [
        "Netflix Assinatura", "Amazon Prime Mensal", "Spotify Family", "HBO Max Streaming"
    ]),
    ("Lazer", "Entreterimento", "NAO_ESSENCIAL", (40.0, 300.0), 5, [
        "Cinema Shopping", "Ingresso Show", "Parque das Aves", "Teatro Municipal"
    ]),
    ("Lazer", "Viagens", "BEM_ESTAR", (250.0, 1500.0), 2, [
        "Hospedagem Booking Pousada", "Passagem Aerea Parcela 2/6", "Passeio Turistico"
    ]),
    ("Pessoal", "Presentes", "NAO_ESSENCIAL", (50.0, 350.0), 3, [
        "Presente Aniversario Amigo", "Presente Dia das Maes", "Lembranca Casamento"
    ]),
    ("Pessoal", "Vestuario", "NAO_ESSENCIAL", (60.0, 420.0), 4, [
        "Renner Roupas", "Zara Shopping", "Centauro Tenis", "Decathlon Esporte"
    ]),
    ("Pet", "Alimentacao_Pet", "OPEX", (70.0, 260.0), 3, [
        "Racao Golden Gatos 10kg", "Petisco Caes Petz", "Sachê Premier Cobasi"
    ]),
    ("Pet", "Veterinario", "OPEX", (120.0, 400.0), 1, [
        "Consulta Vacina Anual", "Banho e Tosa PetShop", "Anti Pulgas Bravecto"
    ]),
    ("Investimento", "Aporte", "INVESTIMENTO", (500.0, 2500.0), 2, [
        "Aporte Tesouro Direto Selic", "Aplicacao Fundo DI", "CDB Liquidez Diaria"
    ]),
    ("Educacao", "Cursos", "FORMACAO", (80.0, 400.0), 2, [
        "Curso Udemy Oracle Database", "Assinatura Alura Anual 3/12", "Livro Engenharia de Dados"
    ])
]

# Construir lista ponderada para amostragem probabilística realista
TAXONOMIA_PONDERADA = []
for item in TAXONOMIA:
    TAXONOMIA_PONDERADA.extend([item] * item[4])

def formatar_valor_ptbr(valor: float) -> str:
    """Converte float em padrão pt-BR com vírgula: 1234.56 -> 1234,56"""
    return f"{valor:.2f}".replace(".", ",")

def formatar_competencia(mes: int, ano: int) -> str:
    """Reproduz o formato de competência corrompido do Excel: MM.AAAA -> 22.023, 112.024"""
    return f"{mes}{ano}"

def gerar_transacao(id_transacao: int, data_transacao: date, lag_fatura_meses: int = 0):
    item = random.choice(TAXONOMIA_PONDERADA)
    cat, subcat, tipo, faixa_val, _, descricoes = item
    
    # Calcular competência a partir da data + lag de cartão de crédito
    ano_comp = data_transacao.year
    mes_comp = data_transacao.month + lag_fatura_meses
    while mes_comp > 12:
        mes_comp -= 12
        ano_comp += 1
        
    comp_str = formatar_competencia(mes_comp, ano_comp)
    resp = random.choice(RESPONSAVEIS)
    desc = random.choice(descricoes)
    
    # Gerar valor dentro da faixa com distribuição normal truncada
    media = (faixa_val[0] + faixa_val[1]) / 2.0
    desvio = (faixa_val[1] - faixa_val[0]) / 4.0
    valor = random.gauss(media, desvio)
    valor = max(faixa_val[0], min(faixa_val[1], valor))
    valor_formatado = formatar_valor_ptbr(valor)
    
    data_formatada = data_transacao.strftime("%d/%m/%Y")
    
    return {
        "id": id_transacao,
        "data": data_formatada,
        "competencia": comp_str,
        "responsavel": resp,
        "descricao": desc,
        "valor": valor_formatado,
        "categoria": cat,
        "subcategoria": subcat,
        "tipo": tipo,
        "observacao": ""
    }

def linha_para_csv(t: dict) -> str:
    return f"{t['id']};{t['data']};{t['competencia']};{t['responsavel']};{t['descricao']};{t['valor']};{t['categoria']};{t['subcategoria']};{t['tipo']};{t['observacao']}"

def gerar_dataset():
    print("Iniciando geração de dataset sintético (5 anos: 2021 a 2025)...")
    INBOX_DIR.mkdir(parents=True, exist_ok=True)
    DATA_INBOX_DIR.mkdir(parents=True, exist_ok=True)
    
    id_global = 1
    todas_transacoes = []
    meses_processados = 0
    
    # 2. Gerar 60 arquivos mensais (2021-01 a 2025-12)
    for ano in range(2021, 2026):
        for mes in range(1, 13):
            meses_processados += 1
            transacoes_mes = []
            
            # Determinar quantidade de dias e transações (média ~65 por mês)
            if mes in [1, 3, 5, 7, 8, 10, 12]:
                num_dias = 31
            elif mes in [4, 6, 9, 11]:
                num_dias = 30
            else:
                num_dias = 29 if ano == 2024 else 28
                
            qtd_transacoes = random.randint(55, 75)
            
            for _ in range(qtd_transacoes):
                dia = random.randint(1, num_dias)
                dt = date(ano, mes, dia)
                # Lag típico de fatura de cartão: 0 (à vista/débito) ou 1 mês adiante
                lag = random.choices([0, 1], weights=[40, 60])[0]
                
                t = gerar_transacao(id_global, dt, lag)
                transacoes_mes.append(t)
                todas_transacoes.append(t)
                id_global += 1
                
            # Salvar remessa mensal
            nome_arquivo = f"orcamento_{ano}_{mes:02d}.csv"
            caminho_arquivo = INBOX_DIR / nome_arquivo
            
            with open(caminho_arquivo, "w", encoding="utf-8") as f:
                f.write("id;data;competencia;responsavel;descricao;valor;categoria;subcategoria;tipo;observacao\n")
                for t in transacoes_mes:
                    f.write(linha_para_csv(t) + "\n")
                    
    print(f"60 remessas mensais geradas com sucesso em: {INBOX_DIR}")
    
    # 3. Gerar arquivo consolidado de 5 anos (full)
    caminho_full = INBOX_DIR / "orcamento_full_5anos.csv"
    with open(caminho_full, "w", encoding="utf-8") as f:
        f.write("id;data;competencia;responsavel;descricao;valor;categoria;subcategoria;tipo;observacao\n")
        for t in todas_transacoes:
            f.write(linha_para_csv(t) + "\n")
            
    print(f"Arquivo consolidado gerado: {caminho_full} ({len(todas_transacoes)} transações)")
    
    # 4. Gerar dataset especial com defeitos propositais para testes de Data Quality (DQ)
    print("Gerando lote de testes com defeitos propositais (orcamento_teste_defeitos.csv)...")
    caminho_defeitos = INBOX_DIR / "orcamento_teste_defeitos.csv"
    
    defeitos_transacoes = []
    # Copia inicial de 20 transações normais
    for i in range(1, 21):
        dt = date(2025, 6, i)
        defeitos_transacoes.append(gerar_transacao(9000 + i, dt, 0))
        
    linhas_defeitos = []
    linhas_defeitos.append("id;data;competencia;responsavel;descricao;valor;categoria;subcategoria;tipo;observacao")
    
    # Casos normais iniciais (amostra com distribuição típica de gastos)
    for t in defeitos_transacoes:
        linhas_defeitos.append(linha_para_csv(t))
        
    # DEFEITO 1: Registros quebrados em duas linhas físicas (quebra embutida na descrição)
    # Reproduz exatamente o achado real de 49 registros partidos
    for k in range(1, 50):
        id_k = 9100 + k
        linha_partida = (
            f"{id_k};15/06/2025;62.025;Responsavel_A;Posto Petrobras BR Linha 1\r\n"
            f"  Continuação da Despesa Parcela {k};185,50;Transporte;Gasolina;OPEX;"
        )
        linhas_defeitos.append(linha_partida)
        
    # DEFEITO 2: Valores com prefixo 'R$' e espaços
    for k in range(1, 11):
        id_k = 9200 + k
        linhas_defeitos.append(f"{id_k};18/06/2025;62.025;Responsavel_B;Compras Diversas;R$ 254,80;Alimentacao;Mercado;OPEX;")
        
    # DEFEITO 3: Valores nulos/vazios (campo financeiro ausente)
    for k in range(1, 6):
        id_k = 9300 + k
        linhas_defeitos.append(f"{id_k};20/06/2025;62.025;Responsavel_A;Farmacia Central;;Saude;Farmacia;BEM_ESTAR;")
        
    # DEFEITO 4: Data ausente/nula
    for k in range(1, 4):
        id_k = 9400 + k
        linhas_defeitos.append(f"{id_k};;62.025;Responsavel_A;Padaria Estrela;45,00;Alimentacao;Restaurante_Delivery;NAO_ESSENCIAL;")
        
    # DEFEITO 5: Descrição ausente/nula
    for k in range(1, 4):
        id_k = 9500 + k
        linhas_defeitos.append(f"{id_k};22/06/2025;62.025;Responsavel_B;;89,90;Moradia;Manutencao_Reparos;OPEX;")
        
    # DEFEITO 6: Duplicidade proposital de chave natural/transação
    id_dup = 9601
    linha_dup = f"{id_dup};23/06/2025;62.025;Responsavel_A;Supermercado Big Bom;312,45;Alimentacao;Mercado;OPEX;"
    linhas_defeitos.append(linha_dup)
    linhas_defeitos.append(linha_dup)  # Linha idêntica duplicada
    
    # DEFEITO 7: Outlier estatístico (> 4x a média da subcategoria)
    id_outlier = 9701
    linhas_defeitos.append(f"{id_outlier};24/06/2025;62.025;Responsavel_A;Ifood Mega Banquete;3850,00;Alimentacao;Restaurante_Delivery;NAO_ESSENCIAL;")
    
    # DEFEITO 8: Lag temporal anômalo (competência 18 meses adiante)
    id_lag = 9801
    linhas_defeitos.append(f"{id_lag};25/06/2025;122.026;Responsavel_B;Compra Futura Fatura;120,00;Alimentacao;Mercado;OPEX;")
    
    # DEFEITO 9: Linhas vazias no final do arquivo (ruído comum de export de planilhas)
    for _ in range(15):
        linhas_defeitos.append(";;;;;;;;;")
        
    with open(caminho_defeitos, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(linhas_defeitos) + "\n")
        
    print(f"Arquivo de testes de defeitos gerado com sucesso: {caminho_defeitos}")
    print("Processamento concluído com êxito!")

if __name__ == "__main__":
    gerar_dataset()
