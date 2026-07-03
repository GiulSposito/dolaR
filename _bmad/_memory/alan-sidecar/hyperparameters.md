---
name: alan-hyperparameters
description: Registro de grids e resultados de tuning de hiperparâmetros para dolaR
metadata:
  type: project
---

# Hyperparameters — dolaR

## Estado atual

Nenhum tuning realizado ainda. Alan ativado pela primeira vez em 2026-07-02.

## Grids planejados (após baseline comparison)

### Ridge / Elastic Net
- `penalty`: log-scale grid [1e-5, 1e2]
- `mixture`: [0, 0.25, 0.5, 0.75, 1.0] (0 = Ridge, 1 = Lasso)

### Random Forest (ranger)
- `mtry`: [sqrt(p), p/3, p/2]
- `min_n`: [5, 10, 20]
- `trees`: 500 (fixo — não tunar)

### XGBoost
- `trees`: [100, 500, 1000]
- `tree_depth`: [3, 6, 8]
- `learn_rate`: [0.01, 0.05, 0.1]
- `min_n`: [5, 10, 20]
- `loss_reduction`: [0, 0.1, 1]
- `sample_size`: [0.7, 0.85, 1.0]

## Resultados de tuning (script 12, LHC 20 configs, 39 folds, 2026-07-02)

| Horizonte | Modelo | Best params | CV RMSE | vs Baseline | Champion? |
|-----------|--------|-------------|---------|-------------|-----------|
| D+5  | Elastic Net | penalty=0.0106, mixture=0.595 | 0.02091 | ~0% melhora | **SIM** |
| D+5  | Random Forest | mtry=10, min_n=13 | 0.02243 | ~0% melhora | não |
| D+30 | Random Forest | mtry=10, min_n=13 | 0.04970 | +0.4% melhora | **SIM** |
| D+30 | XGBoost | mtry=10, min_n=22, depth=5, lr=0.069 | 0.04975 | +8% melhora | não |
| D+90 | Random Forest | mtry=10, min_n=13 | 0.06901 | ~0% melhora | não |
| D+90 | XGBoost | mtry=13, min_n=13, depth=9, lr=0.022 | **0.06884** | +10% melhora | **SIM** |

## Champions finais (fit em train_val completo)

| Horizonte | Champion | CV RMSE | Arquivo |
|-----------|----------|---------|---------|
| D+5  | Elastic Net | 0.02091 | models/tuned/champion-target_5d.rds |
| D+30 | Random Forest | 0.04970 | models/tuned/champion-target_30d.rds |
| D+90 | XGBoost | 0.06884 | models/tuned/champion-target_90d.rds |

Nota: ARIMA D+5 = 0.01570 — ainda melhor que ElasticNet tunado no CV.
