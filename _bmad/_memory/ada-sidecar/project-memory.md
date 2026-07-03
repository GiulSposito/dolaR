---
name: ada-project-memory
description: Contexto e estado do projeto dolaR — Ada sidecar
metadata:
  type: project
---

# Projeto dolaR — Memória Ada

## Contexto geral

**Objetivo:** Prever USD/BRL nos horizontes D+5, D+30 e D+90 usando R.
**Abordagem:** Retornos logarítmicos (não preços brutos) para garantir estacionariedade.
**Stack:** R + RStudio + VS Code + Claude Code + Helix DS framework.
**Modelo mental:** Três modelos independentes, um por horizonte.

## Decisões de arquitetura tomadas

- **Target:** retorno log `= log(usd_brl[t+H] / usd_brl[t])`, não preço bruto.
- **Validação:** walk-forward obrigatório (nunca split aleatório).
- **Data de disponibilidade:** regra crítica — cada variável só entra no dataset a partir do dia em que estava disponível no mercado. Séries mensais usam `tidyr::fill(.direction = "down")`.
- **renv:** recomendado, inicializar com `renv::init()` no RStudio após o setup.
- **MVP foco:** Etapa 1 — coleta de dados + baselines (Random Walk, ARIMA, Ridge) antes de ML complexo.

## Estado atual (2026-07-02)

**Fase 1 concluída:**
- [x] Estrutura de diretórios, `.gitignore`, `.Rprofile`, `.Renviron.local.template`
- [x] `README.md`, feriados, dicionário de dados, scripts 01–08 criados
- [x] `01-setup.R` executado (checkpoint: 12:19)
- [ ] `renv::init()` — aguardando execução manual no RStudio

**Fase 2 concluída (coleta — todos executados em 2026-07-02):**
- [x] `02-collect-market.R` → PTAX (4.142 obs) + Yahoo 11 tickers (12:20)
- [x] `03-collect-macro-br.R` → BCB SGS + Focus + IBGE IPCA (12:28)
- [x] `04-collect-macro-us.R` → FRED 10 séries (12:21)
- [x] `07-collect-fiscal-activity.R` → BCB SGS fiscal/atividade + IBGE PIM/PNAD (13:41)
- [x] `08-collect-global-indicators.R` → FRED commodities + breakevens + HY spread (13:48)
- [ ] `05-collect-b3.R` — placeholder (DOL=F indisponível; BVSP já em Yahoo)

**Fase 4 iniciada (Grace ativada 2026-07-02):**
- [x] `09-eda.R` criado — Grace sidecar inicializado
- [ ] `09-eda.R` executado no RStudio

**Fase 3 concluída (dataset):**
- [x] `06-build-dataset.R` → `daily_dataset.rds` e `model_dataset.rds` (13:48)
  - 9 fontes integradas: ptax, yahoo, sgs, fred, focus, ibge, sgs_fiscal, activity_sidra, fred_add
  - **60 variáveis totais**, 4.142 linhas (2010-01-04 a 2026-07-01)
  - Dataset para modelagem: 4.052 obs (últimas 90 sem target removidas)

**Próxima ação:** Executar `scripts/09-eda.R` no RStudio (Fase 4 — EDA exploratório)

## Fontes de dados mapeadas e status

| Fonte | Pacote R | Chave API | Status |
|-------|----------|-----------|--------|
| BCB PTAX | rbcb | nenhuma | ✅ coletado |
| BCB SGS (diário/mensal) | rbcb | nenhuma | ✅ coletado |
| BCB SGS (fiscal/atividade) | rbcb | nenhuma | ✅ coletado |
| BCB Focus | rbcb | nenhuma | ✅ coletado |
| IBGE SIDRA IPCA | sidrar | nenhuma | ✅ coletado |
| IBGE SIDRA PIM/PNAD | sidrar | nenhuma | ✅ coletado |
| Yahoo Finance | tidyquant | nenhuma | ✅ coletado |
| FRED (principal) | fredr | FRED_API_KEY | ✅ coletado |
| FRED (adicional) | fredr | FRED_API_KEY | ✅ coletado |
| ANBIMA curva de juros | httr2 | CLIENT_ID/SECRET | ❌ sandbox apenas (401) |
| B3 futuros | cotahist | nenhuma | ❌ pendente pós-MVP |
| Comex Stat | httr2 | nenhuma | ❌ 403 Forbidden |

## 60 variáveis no dataset final

**Mercado (diárias):** usd_brl_ptax, usd_brl, dxy, dxy_fred, vix, vix_fred, ewz, ibovespa, sp500, nasdaq, petroleo_brent, petroleo_wti, ouro, cobre, treasury_2y, treasury_10y, sofr, reservas_intl, cdi_diario, selic_diaria, breakeven_10y, breakeven_5y, us_hy_spread

**Macro BR (mensais, forward-fill):** selic_meta, ipca_mensal, ipca_acum12m, fluxo_cambial, saldo_cambial, resultado_primario, resultado_nominal, dbgg_pib, balanca_comercial_bcb, ibc_br, desemprego_br, pim_geral, ipca_variacao_* (5 cols SIDRA)

**Macro EUA (mensais, forward-fill):** fed_funds, cpi_us, core_cpi_us, pce_us, desemprego_us, minerio_ferro, soja, consumer_sentiment_us

**Expectativas (semanais, forward-fill):** focus_cambio, focus_selic, focus_ipca, focus_pib_total

**Atividade trimestral (forward-fill):** desemprego_pnad_trimestral

**Targets:** target_5d, target_30d, target_90d, dir_5d, dir_30d, dir_90d

## Problemas conhecidos / avisos

- `saldo_cambial` (SGS 23636): apenas 14 obs — série irregular, considerar remover no EDA.
- `us_hy_spread` (FRED BAMLH0A0HYM2): disponível apenas a partir de 2023-07 (não 2010).
- `pim_geral` (SIDRA 3653): vai até jan/2022 — gap de ~4 anos até hoje.
- `sofr`: NA antes de 2018-04 (série criada em 2018).
- CDS Brasil direto: ausente — EWZ como proxy.
- ANBIMA curva juros: credencial sandbox não acessa endpoints de preços.
