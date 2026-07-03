# Plano de Setup — dolaR

## Contexto

Projeto de data science em R para prever USD/BRL nos horizontes D+5, D+30 e D+90.
Foco inicial: MVP Etapa 1 — coletar dados de múltiplas APIs, montar dataset diário, rodar baselines.
Ferramentas: R + RStudio + VS Code + Claude Code. Gestão de pacotes: renv (recomendado).

---

## O que já existe

- `dolaR.Rproj` (RStudio project file, configurações básicas)
- `README.md` (mínimo, só título)
- `docs/briefing.md` + `docs/datasources.md`
- `.gitignore` (recém criado)
- `.claude/skills/` (skills do helix)
- `_bmad/` (framework de workflows)

---

## Decisões de design

### Estrutura de diretórios adaptada ao projeto

O workflow RDS padrão (`step-01-setup.md`) usa `scripts/01-NN.R`.
Para este projeto de séries temporais com múltiplas fontes de dados, a estrutura será adaptada:

```
dolaR/
├── R/                          # Funções reutilizáveis (pacotes-style)
│   ├── collect/                # Funções de coleta por fonte
│   ├── features/               # Funções de engenharia de atributos
│   └── utils/                  # Helpers gerais
├── scripts/
│   ├── 01-setup.R              # Verificação do ambiente
│   ├── 02-collect-market.R     # BCB PTAX, Yahoo Finance
│   ├── 03-collect-macro-br.R   # BCB SGS, Focus, IBGE, Ipeadata
│   ├── 04-collect-macro-us.R   # FRED (juros EUA, VIX, CPI)
│   ├── 05-collect-b3.R         # B3 futuros DI/dólar
│   ├── 06-build-dataset.R      # Join e alinhamento temporal
│   ├── 07-eda.R                # EDA da série principal
│   ├── 08-features.R           # Lags, MMs, volatilidade, calendário
│   ├── 09-baseline.R           # Random Walk, ARIMA, Ridge
│   └── 10-evaluate.R           # Walk-forward validation + métricas
├── data/
│   ├── raw/                    # Respostas originais das APIs (gitignored)
│   │   ├── bcb_ptax/
│   │   ├── bcb_sgs/
│   │   ├── bcb_focus/
│   │   ├── fred/
│   │   ├── yahoo/
│   │   ├── ibge/
│   │   └── b3/
│   ├── processed/              # Dataset unificado (gitignored)
│   └── reference/              # Dados estáticos pequenos (versionados)
│       └── br_holidays.csv     # Feriados BR para features de calendário
├── models/                     # Artefatos de modelos (gitignored)
├── outputs/
│   ├── figures/                # Gráficos EDA e diagnósticos
│   └── tables/                 # Métricas, dicionário de dados
├── reports/
│   ├── eda-report.qmd
│   └── baseline-report.qmd
├── checkpoints/                # Marcadores de fase (.complete)
├── logs/                       # Logs de execução
├── renv/                       # Infraestrutura renv
└── _bmad/                      # Framework (já existe)
```

### Separação data/raw vs data/reference

- `data/raw/` → gitignored (dados de API, potencialmente grandes)
- `data/reference/` → versionado (feriados BR, calendário Copom/FOMC, pequenos arquivos estáticos)
- `data/processed/` → gitignored

### Pacotes R (MVP)

Núcleo de dados e manipulação:
- `tidyverse` — manipulação geral
- `lubridate` — datas
- `here` — paths
- `conflicted` — resolução de conflitos

Coleta de dados:
- `rbcb` — BCB PTAX, SGS, Focus (substitui python-bcb)
- `quantmod` ou `tidyquant` — Yahoo Finance (USD/BRL, DXY, VIX, bolsas)
- `fredr` — FRED API (juros EUA, Treasury, CPI)
- `sidrar` — IBGE SIDRA

Inspeção e qualidade:
- `skimr` — profiling
- `janitor` — limpeza de nomes
- `naniar` — missing values

Modelagem (MVP baselines):
- `tidymodels` — framework unificado
- `forecast` ou `fable` — ARIMA, ARIMA + validação temporal
- `timetk` — utilitários de séries temporais

Visualização:
- `ggplot2` (incluso no tidyverse)
- `patchwork` — composição de plots
- `scales` — formatação de eixos

Reports:
- `quarto` (via IDE, não pacote R)
- `gt` — tabelas formatadas

### Credenciais de API

APIs que requerem chave:
- **FRED** — `fredr_set_key()`, armazenar em `.Renviron` como `FRED_API_KEY`
- **EIA** — futura fase, `EIA_API_KEY`

APIs públicas sem chave no MVP:
- BCB (PTAX, SGS, Focus) — abertas
- IBGE SIDRA — aberta
- Yahoo Finance — via `quantmod`/`tidyquant`

Arquivo `.Renviron.local` será criado com template (sem valores reais).

### Targets (variáveis-alvo)

Seguindo o briefing, prever **retornos** e não preços:
- `target_5d  = (close[t+5]  / close[t]) - 1`
- `target_30d = (close[t+30] / close[t]) - 1`
- `target_90d = (close[t+90] / close[t]) - 1`

### Validação temporal

Walk-forward (não aleatória), conforme briefing.
O split train/test padrão do `recipes` **não** será usado diretamente —
usar `timetk::time_series_split()` ou splits manuais.

---

## Ações do plano (o que será criado)

### 1. Atualizar dolaR.Rproj
Ajustar configurações: sem salvar workspace, sem restaurar workspace.

### 2. Criar estrutura de diretórios
Todos os diretórios listados acima + arquivos `.gitkeep` onde necessário.

### 3. Criar .Rprofile
Ativação do renv + opções globais úteis (scipen, encoding).

### 4. Criar .Renviron.local.template
Template documentado para chaves de API.

### 5. Criar scripts/01-setup.R
Verifica estrutura, carrega conflicted, define opções globais.

### 6. Criar scripts/02-collect-market.R
Funções comentadas para BCB PTAX e Yahoo Finance (USD/BRL, DXY, VIX, S&P500, Ibovespa, Brent/WTI).

### 7. Criar scripts/03-collect-macro-br.R
Funções para BCB SGS (Selic, CDI, IPCA) e BCB Focus (câmbio, Selic, IPCA esperados).

### 8. Criar scripts/04-collect-macro-us.R
Funções para FRED (Treasury 2Y/10Y, Fed Funds, VIX, CPI EUA).

### 9. Criar scripts/06-build-dataset.R
Join temporal, alinhamento de frequências, criação dos targets 5d/30d/90d.
Inclui aviso sobre data de disponibilidade (sem leakage).

### 10. Criar data/reference/br_feriados.csv
Feriados nacionais BR para features de calendário (pequeno, versionado).

### 11. Criar outputs/tables/data_dictionary_template.csv
Template de dicionário de variáveis (a preencher na fase de EDA).

### 12. Atualizar README.md
Descrição do projeto, instruções de setup, fases do workflow, mapa de fontes de dados.

### 13. Criar _bmad/_memory/ada-sidecar/project-memory.md
Memória de projeto para Ada (contexto, decisões, estado atual).

### 14. Criar _bmad/_memory/ada-sidecar/cleaning-decisions.md
Log de decisões de limpeza (vazio no início, preenchido conforme avançamos).

### 15. Criar _bmad/_memory/ada-sidecar/data-quality-log.md
Log de qualidade de dados (vazio no início).

### 16. Criar checkpoints/ com marcador de fase 1

---

## O que NÃO será feito agora

- `renv::init()` — requer execução no RStudio (será instruído, não automatizado)
- Scripts 05, 07-10 — são fases posteriores
- Coleta real de dados — apenas estrutura e scripts de coleta
- Modelos — fase posterior
- Reports Quarto — fase posterior

---

## Arquivos que serão MODIFICADOS

- `dolaR.Rproj` — ajuste de configurações
- `README.md` — reescrita completa

## Arquivos que serão CRIADOS

Ver lista de ações acima (itens 3-16 + estrutura de diretórios).

---

_Plano gerado por Ada | 2026-07-02_
