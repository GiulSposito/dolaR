---
name: grace-feature-registry
description: Registro de features criadas e avaliadas para o projeto dolaR
metadata:
  type: project
---

# Feature Registry — dolaR

## Estado

- Script `10-feature-engineering.R` criado em 2026-07-02 — aguardando execução no RStudio
- 54 features engenheiradas planejadas em 5 grupos

## Features brutas disponíveis (do dataset)

### Mercado diário
usd_brl_ptax, usd_brl, dxy, dxy_fred, vix, vix_fred, ewz, ibovespa, sp500, nasdaq,
petroleo_brent, petroleo_wti, ouro, cobre, treasury_2y, treasury_10y, sofr,
reservas_intl, cdi_diario, selic_diaria, breakeven_10y, breakeven_5y, us_hy_spread

### Macro BR (mensais, forward-fill)
selic_meta, ipca_mensal, ipca_acum12m, fluxo_cambial, ~~saldo_cambial~~,
resultado_primario, resultado_nominal, dbgg_pib, balanca_comercial_bcb,
ibc_br, desemprego_br, pim_geral, ipca_variacao_* (5 cols SIDRA)

### Macro EUA (mensais, forward-fill)
fed_funds, cpi_us, core_cpi_us, pce_us, desemprego_us, minerio_ferro, soja, consumer_sentiment_us

### Expectativas (semanais, forward-fill)
focus_cambio, focus_selic, focus_ipca, focus_pib_total

### Atividade trimestral
desemprego_pnad_trimestral

## Features engenheiradas criadas (script 10-feature-engineering.R)

### G1 — Retornos e Momentum USD/BRL (14 features)
- `ret_usd_1d`, `ret_usd_5d`, `ret_usd_10d`, `ret_usd_21d`, `ret_usd_63d`
- `ma_usd_5d`, `ma_usd_21d`, `ma_usd_63d`
- `dist_ma_5d`, `dist_ma_21d`, `dist_ma_63d` (posição relativa à média)
- `max_63d`, `min_63d`, `drawdown_63d`, `range_63d`

### G2 — Volatilidade Realizada (6 features)
- `vol_usd_5d`, `vol_usd_21d`, `vol_usd_63d` (anualizada, sd dos retornos diários)
- `vol_ratio` = vol_5d / vol_21d (spike de vol)
- `ret_vix_1d` (auxiliar), `vol_vix_21d`

### G3 — Spreads Macrofinanceiros (10 features)
- `spread_selic_fed` = selic_meta - fed_funds (carry trade)
- `spread_cdi_sofr` = cdi_diario*252 - sofr (carry diário)
- `spread_10y_2y_us` = treasury_10y - treasury_2y (curva EUA)
- `spread_ipca_cpi` = ipca_acum12m - cpi_us (diferencial inflação)
- `ret_ewz_5d`, `ret_ewz_21d` (proxy CDS Brasil)
- `fluxo_acum_21d`, `fluxo_acum_63d` (pressão de oferta/demanda)

### G4 — Retornos Externos (16 features)
- `ret_dxy_1d`, `ret_dxy_5d`, `ret_dxy_21d`
- `ret_vix_5d`, `ret_vix_21d`
- `ret_oil_5d`, `ret_oil_21d` (brent)
- `ret_ferro_5d`, `ret_ferro_21d`
- `ret_ouro_5d`, `ret_ouro_21d`
- `ret_ibov_5d`, `ret_ibov_21d`
- `ret_sp500_5d`, `ret_sp500_21d`
- `erro_focus` = log(focus_cambio / usd_brl_ptax)

### G5 — Calendário (8 features)
- `dia_semana`, `mes`, `trimestre`, `semana_do_ano`
- `fim_de_mes` (dummy 0/1)
- `mes_copom`, `mes_fomc` (dummies de meses típicos)

## Decisões de descarte

- `saldo_cambial`: descartada — apenas 14 obs úteis (Ada recomendou no EDA)
- `us_hy_spread`: cobertura apenas desde 2023-07 — usar com cautela, avaliar no modeling
- `pim_geral`: gap de ~4 anos (até jan/2022) — forward-fill cria ruído; avaliar remoção
- `sofr`: NAs antes de 2018-04 — avaliar imputação vs remoção para modelo D+5

## Output gerado

- `data/processed/features_dataset.rds`
- `outputs/tables/fe-feature-completude.csv`
- `outputs/tables/fe-correlation-features.csv`
- `reports/10-fe-summary.txt`
