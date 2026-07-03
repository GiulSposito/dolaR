---
name: grace-visualization-library
description: Biblioteca de visualizações criadas e aprovadas para o projeto dolaR
metadata:
  type: project
---

# Visualization Library — dolaR

## Estado

- Sidecar inicializado em 2026-07-02 (pré-EDA)
- Plots ainda não gerados

## Plots planejados para 09-eda.R

### Série temporal do target
- USD/BRL PTAX ao longo do tempo (2010–2026)
- Distribuição dos três targets (D+5, D+30, D+90) — histograma + densidade
- Série de retornos diários com destaque para eventos extremos

### Qualidade dos dados
- Missing data por variável (naniar::gg_miss_var)
- Heatmap de disponibilidade temporal por fonte (quando cada série começa)

### Correlação
- Corrplot das variáveis de mercado vs target_30d
- Scatter de focus_cambio vs target_30d (hipótese principal)

### Análise por horizonte
- Autocorrelação (ACF) dos três targets
- Volatilidade do USD/BRL ao longo do tempo (rolling 60d)

## Plots gerados

_(preencher após execução do 09-eda.R)_
