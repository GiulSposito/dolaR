---
name: alan-features-used
description: Features selecionadas para cada modelo e decisões de feature engineering para dolaR
metadata:
  type: project
---

# Features Used — dolaR

## Estado atual

Feature engineering (script `10-feature-engineering.R`) criado por Grace em 2026-07-02 — aguardando execução.
Output esperado: `data/processed/features_dataset.rds` com ~54 features engenheiradas + originais.

## Feature groups disponíveis (Grace registry)

### G1 — Retornos e Momentum USD/BRL (14 features)
`ret_usd_1d`, `ret_usd_5d`, `ret_usd_10d`, `ret_usd_21d`, `ret_usd_63d`,
`ma_usd_5d`, `ma_usd_21d`, `ma_usd_63d`, `dist_ma_5d`, `dist_ma_21d`, `dist_ma_63d`,
`max_63d`, `min_63d`, `drawdown_63d`, `range_63d`

### G2 — Volatilidade Realizada (6 features)
`vol_usd_5d`, `vol_usd_21d`, `vol_usd_63d`, `vol_ratio`, `ret_vix_1d`, `vol_vix_21d`

### G3 — Spreads Macrofinanceiros (10 features)
`spread_selic_fed`, `spread_cdi_sofr`, `spread_10y_2y_us`, `spread_ipca_cpi`,
`ret_ewz_5d`, `ret_ewz_21d`, `fluxo_acum_21d`, `fluxo_acum_63d`, `erro_focus`

### G4 — Retornos Externos (16 features)
`ret_dxy_1d`, `ret_dxy_5d`, `ret_dxy_21d`, `ret_vix_5d`, `ret_vix_21d`,
`ret_oil_5d`, `ret_oil_21d`, `ret_ferro_5d`, `ret_ferro_21d`,
`ret_ouro_5d`, `ret_ouro_21d`, `ret_ibov_5d`, `ret_ibov_21d`,
`ret_sp500_5d`, `ret_sp500_21d`

### G5 — Calendário (8 features)
`dia_semana`, `mes`, `trimestre`, `semana_do_ano`, `fim_de_mes`, `mes_copom`, `mes_fomc`

## Features problemáticas (atenção)

| Feature | Problema | Decisão |
|---------|---------|---------|
| `us_hy_spread` | Apenas desde 2023-07 | Avaliar durante modeling — possível remoção |
| `pim_geral` | Gap de ~4 anos até jan/2022 | Avaliar remoção — forward-fill cria ruído |
| `sofr` | NAs antes de 2018-04 | Imputação vs remoção a decidir |
| `saldo_cambial` | Apenas 14 obs | Descartada (confirmado por Ada) |

## Features selecionadas por modelo

| Horizonte | Feature set | N features | Decisão | Data |
|-----------|------------|------------|---------|------|
| — | — | — | — | — |

## Recipe tidymodels (a criar em Step 1)

- Normalização: `step_normalize()` para modelos lineares
- Encoding calendário: `step_dummy()` para categoricals
- Imputação: `step_impute_median()` para sofr/pim_geral (a decidir)
- Remoção near-zero variance: `step_nzv()`
