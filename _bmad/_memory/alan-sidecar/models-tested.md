---
name: alan-models-tested
description: Registro de todos os modelos treinados e comparados no projeto dolaR
metadata:
  type: project
---

# Models Tested — dolaR

## Estado atual

Script `11-modeling.R` criado em 2026-07-02 — aguardando execução no RStudio.
5 modelos × 3 horizontes planejados. Nenhum resultado de CV ainda.

## Baseline concluído (scripts 11 + 11b, 2026-07-02)

## Resultados baseline (walk-forward CV, 39 folds, 2026-07-02)

| Horizonte | Modelo | CV RMSE | CV RMSE SE | Nota |
|-----------|--------|---------|------------|------|
| D+5  | Null (random walk) | 0.0209 | 0.00107 | benchmark |
| D+5  | Elastic Net | 0.0209 | 0.00107 | empata com null — sem sinal linear |
| D+5  | Random Forest | 0.0224 | 0.00125 | |
| D+5  | Ridge | 0.0235 | 0.00125 | |
| D+5  | XGBoost | 0.0253 | 0.00137 | |
| D+30 | Random Forest | 0.0491 | 0.00447 | **melhor** — bate null |
| D+30 | Null | 0.0519 | 0.00384 | benchmark |
| D+30 | XGBoost | 0.0543 | 0.00503 | |
| D+30 | Elastic Net | 0.0568 | 0.00467 | |
| D+30 | Ridge | 0.0670 | 0.00592 | |
| D+90 | Random Forest | 0.0690 | 0.00611 | **melhor** — bate null por largo |
| D+90 | XGBoost | 0.0764 | 0.00785 | |
| D+90 | Elastic Net | 0.0797 | 0.00703 | |
| D+90 | Ridge | 0.0816 | 0.00732 | |
| D+90 | Null | 0.0863 | 0.00823 | benchmark |

## ARIMA baseline (script 11b, walk-forward manual, 2026-07-02)

| Horizonte | ARIMA RMSE | vs Null | Interpretação |
|-----------|-----------|---------|---------------|
| D+5  | 0.0157 | **-25%** (ARIMA MELHOR que null) | Autocorrelação de curto prazo capturada |
| D+30 | 0.0614 | +18% (ARIMA PIOR que null) | Horizonte médio sem sinal ARIMA |
| D+90 | 0.100  | +16% (ARIMA PIOR que null) | Horizonte longo sem sinal ARIMA |

## Ranking completo (RMSE walk-forward CV)

| Modelo | D+5 | D+30 | D+90 |
|--------|-----|------|------|
| **ARIMA** | **0.0157** | 0.0614 | 0.100 |
| Null | 0.0209 | 0.0519 | 0.0863 |
| Elastic Net | 0.0209 | 0.0568 | 0.0797 |
| **RF** | 0.0224 | **0.0491** | **0.0690** |
| XGBoost | 0.0253 | 0.0543 | 0.0764 |
| Ridge | 0.0235 | 0.0670 | 0.0816 |

## Resultados no TEST SET (script 13, 2026-07-02 — toque único)

| Horizonte | Champion | Test RMSE | CV RMSE | Diff | Dir. Accuracy | Hit Ratio |
|-----------|----------|-----------|---------|------|--------------|-----------|
| D+5  | Elastic Net | **0.0159** | 0.0209 | -24% | 49.3% | 49.3% |
| D+30 | Random Forest | **0.0363** | 0.0497 | -27% | 61.0% | 61.0% |
| D+90 | XGBoost | **0.0554** | 0.0688 | -20% | 58.4% | 58.4% |

Nota: test RMSE < CV RMSE em todos os horizontes — período de teste (2022-2026)
foi menos volátil que o período de treino (2010-2022, inclui Covid/2020).

ARIMA D+5 benchmark (CV): 0.01570 — ElasticNet test (0.0159) praticamente empata.

## Candidatos para tuning (Step 3)

| Horizonte | Candidato 1 | Candidato 2 | Nota |
|-----------|------------|------------|------|
| D+5  | ARIMA (0.0157) | Elastic Net (0.0209) | ARIMA vence — avaliar ARIMAX |
| D+30 | Random Forest (0.0491) | XGBoost (0.0543) | |
| D+90 | Random Forest (0.0690) | XGBoost (0.0764) | |
