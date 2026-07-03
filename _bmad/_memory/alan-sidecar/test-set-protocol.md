---
name: alan-test-set-protocol
description: Protocolo de data budgeting e validação walk-forward para dolaR
metadata:
  type: project
---

# Test Set Protocol — dolaR

## Regras sagradas

1. **Test set nunca é tocado** até Step 4 (avaliação final) — ONE TOUCH ONLY.
2. **Walk-forward obrigatório** — nunca split aleatório em séries temporais.
3. **Preprocessing DENTRO dos folds** — imputação, normalização, encoding: NUNCA vazar do treino pro val.
4. **Horizontes independentes** — cada modelo D+5, D+30, D+90 tem seu próprio split.

## Estratégia de split

- **Dataset total:** 4.052 obs (2010-01-04 a ~2025-06-xx)
- **Test set (holdout final):** últimos 20% cronológicos (~810 obs / ~3.2 anos)
- **Training+Validation:** primeiros 80% (~3.242 obs)
- **CV strategy:** `rsample::sliding_window()` — walk-forward com janela rolante
  - Window size: 756 obs (~3 anos)
  - Step: 63 obs (~1 trimestre)
  - Min assessment: 63 obs

## Estado atual

- [x] Split codificado em `11-modeling.R` (linhas 67-85) — execução pendente no RStudio
- [x] `models/test_data.rds` — gerado em 2026-07-02 (810 obs, 2022-11-30 a 2026-02-19)

## Datas de corte (a confirmar após dados)

| Conjunto | Início | Fim | N obs |
|----------|--------|-----|-------|
| Train+Val | 2010-01-04 | ~2022-10 | ~3.242 |
| Test | ~2022-10 | 2025-06 | ~810 |
