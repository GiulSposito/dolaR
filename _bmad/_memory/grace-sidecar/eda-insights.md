---
name: grace-eda-insights
description: EDA insights acumulados para o projeto dolaR (USD/BRL prediction)
metadata:
  type: project
---

# EDA Insights — dolaR

## Estado

- Sidecar inicializado em 2026-07-02 (primeira ativação de Grace)
- Script `09-eda.R` executado (checkpoint: `04-eda.complete`)
- Script `10-feature-engineering.R` executado (checkpoint: `05-feature-engineering.complete`)

## Estrutura dos dados confirmada

- **model_dataset:** 4.052 obs × 60 vars (2010-01-04 a 2026-02-19)
- **features_dataset:** 4.052 obs × 111 vars (60 brutas + 52 engenheiradas - 1 descartada)

## Problemas confirmados no EDA / Feature Engineering

### Séries mensais sem forward-fill no model_dataset
- `fed_funds`, `cpi_us`, `core_cpi_us`, `fluxo_cambial` e outras mensais chegam com NAs nos dias sem publicação
- **Solução aplicada:** forward-fill em 16 séries no `10-feature-engineering.R` (23.520 células preenchidas)
- **Lição:** o `build-dataset` fez forward-fill em algumas séries mas não em todas — verificar no `11-modeling.R`

### Features com baixa cobertura (< 80%)
| Feature | Cobertura | Causa |
|---------|-----------|-------|
| `spread_cdi_sofr` | 34.6% | sofr só disponível desde 2018-04 |
| `vol_vix_21d` | 48.4% | VIX com NAs no início da série |

### Séries problemáticas conhecidas
- `saldo_cambial`: descartada (<14 obs úteis)
- `us_hy_spread`: disponível só de 2023-07 (~3 anos)
- `pim_geral`: vai até jan/2022 — gap de ~4 anos
- `sofr`: NA antes de 2018-04

## Top correlações com target_30d (confirmadas)

| Feature | Cor | N obs |
|---------|-----|-------|
| spread_cdi_sofr | -0.194 | 1.402 |
| vol_vix_21d | +0.151 | 1.961 |
| ret_oil_21d | -0.146 | 3.769 |
| max_63d / ma_usd_63d / vol_usd_63d | ~-0.13 | ~3.990 |
| ret_ibov_21d | -0.107 | 3.924 |
| spread_selic_fed | -0.088 | 3.499 |
| fluxo_acum_21d | +0.082 | 4.012 |
| erro_focus | +0.080 | 4.052 |

**Obs:** correlações lineares baixas (~0.1–0.2) são esperadas em câmbio — modelos não-lineares (XGBoost/LightGBM) devem capturar mais sinal.

## Hipóteses do briefing — status após EDA

| Hipótese | Status |
|----------|--------|
| VIX tem correlação positiva com target (BRL deprecia em stress) | ✅ Confirmado: vol_vix_21d cor=+0.151 |
| focus_cambio é preditor forte | ⚠️ Parcial: erro_focus cor=+0.080 — fraco linearmente |
| D+90 tem maior variância | A confirmar via distribuição dos targets |
| spread_selic_fed captura carry trade | ✅ Presente: cor=-0.088, cobertura boa após ff |

## Obs completas no features_dataset

- 693 obs completas (17.1%) — baixo porque sofr (2018+) e VIX com NAs puxam para baixo
- Para modelos: usar `na.rm` ou imputação, ou filtrar por janela disponível (2018+)
