# Plano: Relatório Técnico Completo — dolaR

## Objetivo

Criar `reports/technical-report.qmd` — relatório técnico completo, tom educacional, em português,
que combina o `docs/briefing.md` com todos os resultados do pipeline (EDA → Feature Engineering →
Modelagem → Tuning → Avaliação Final).

---

## Arquivo de saída

`reports/technical-report.qmd`

Formato: Quarto HTML (`embed-resources: true`) — renderizável com `quarto render` diretamente no projeto.
Idioma: português (pt-BR)
Audience: data scientists / analistas técnicos

---

## Estrutura do relatório (capítulos planejados)

### Capa / Header YAML

```yaml
title: "dolaR — Previsão do USD/BRL"
subtitle: "Relatório Técnico · Pipeline completo de modelagem (D+5, D+30, D+90)"
author: "Helix DS · Marie"
date: today
lang: pt
format:
  html:
    theme: cosmo
    toc: true
    toc-depth: 4
    toc-location: left
    embed-resources: true
    code-fold: true
    code-summary: "Ver código"
    fig-width: 11
    fig-height: 6
    df-print: paged
execute:
  echo: false
  warning: false
  message: false
```

---

### Capítulo 1 — Contexto e Definição do Problema

- Por que prever câmbio é difícil (mercado eficiente, regime-breaks, macro vs micro prazo)
- Retornos logarítmicos vs preço bruto: teoria da estacionariedade, ADF test conceitual
- Hipótese central: drivers diferem por horizonte (teoria + evidência posterior)
- Fórmula matemática do target
- Tabela: três modelos independentes, por que essa arquitetura

### Capítulo 2 — Fontes de Dados e Modelo de Entrada

- 9 fontes integradas: o que cada uma captura economicamente
- Tabela completa com Fonte | Pacote R | Tipo | Freq | N vars | Início | Status
- **Educacional:** para cada grupo de dados, 1–2 parágrafos de teoria econômica:
  - **Mercado diário:** DXY (força global do USD), VIX (aversão a risco), EWZ (proxy CDS Brasil),
    yield curve EUA (slope = 10y-2y: sinal de política monetária), breakevens
  - **Macro BR:** PTAX, Selic/CDI, IPCA, fluxo cambial, resultado fiscal/DBGG — teoria do câmbio de equilíbrio
  - **Macro EUA:** Fed Funds, CPI/PCE, desemprego — importância para USD global
  - **Expectativas (Focus):** mercado já incorpora informação → hipótese de eficiência de mercado
  - **Commodities:** termos de troca Brasil — petróleo, minério, soja
- Modelo de dados de entrada: estrutura da tabela diária, problema do leakage temporal
- Forward-fill de séries mensais/semanais: o problema e a solução correta
- Séries problemáticas: saldo_cambial (descartado), us_hy_spread (cobertura ~12%), pim_geral, sofr

### Capítulo 3 — EDA: Análise Exploratória

- **3.1 Série temporal do USD/BRL (2010–2026)**
  - Eventos marcantes: crise 2015, COVID 2020, eleições 2022, fiscal 2024
  - Plot `outputs/figures/eda-01-usd-brl-ptax.png`
  - Leitura: depreciação secular → confirma que modelos devem operar sobre retornos

- **3.2 Retornos diários**
  - Plot `outputs/figures/eda-02-retornos-diarios.png`
  - Clustered volatility: períodos de alta volatilidade se agrupam (efeito ARCH/GARCH)
  - Implicação: volatilidade passada pode prever volatilidade futura

- **3.3 Distribuição dos targets (D+5, D+30, D+90)**
  - Plot `outputs/figures/eda-03-dist-targets.png` + `eda-04-boxplot-targets.png`
  - Tabela de estatísticas: dp cresce 2%→4,9%→8,5% com o horizonte
  - Caudas pesadas vs Normal: implicação para RMSE

- **3.4 Autocorrelação dos targets**
  - Plot `outputs/figures/eda-11-acf-targets.png`
  - D+5 ≈ ruído branco (confirma hipótese de mercado eficiente em curto prazo)
  - D+30/D+90: autocorrelação positiva → tendência → ARIMA captura isso em D+5

- **3.5 Missing values e cobertura**
  - Plot `outputs/figures/eda-05-missing-vars.png`
  - Decisões tomadas: quais séries foram descartadas e por quê

- **3.6 Correlações com os targets**
  - Plot `outputs/figures/eda-06-cor-features-target30d.png`
  - **Insight chave:** correlações são fracas em D+5 (mercado eficiente curto prazo),
    mais fortes em D+90 (macro domina)
  - Focus câmbio: scatter `eda-10-focus-vs-target30d.png` — hipótese parcialmente confirmada

- **3.7 Correlação entre variáveis de mercado**
  - Plot `outputs/figures/eda-07-corrplot-mercado.png`
  - Pares altamente correlacionados (|r|>0.85): Brent×WTI, Nasdaq×S&P → redundância

- **3.8 Volatilidade e regimes de mercado**
  - Plot `outputs/figures/eda-08-volatilidade-usdbrl.png`
  - Conceito de regime-break: por que janela deslizante foi preferida a janela expansiva

### Capítulo 4 — Feature Engineering

- **4.1 Filosofia:** features devem capturar o passado do mercado, não o futuro — "no data leakage"
- **4.2 G1 — Retornos e Momentum (14 features)**
  - Fórmulas: ret_usd_Nd, MA, distância da MA, drawdown_63d, range_63d
  - Por que momentum: hipótese de momentum de Jegadeesh & Titman, carry over em câmbio

- **4.3 G2 — Volatilidade Realizada (6 features)**
  - vol_usd_5d/21d/63d, vol_ratio, vol_vix_21d
  - GARCH intuitivo: vol presente prediz vol futura → amplificador de incerteza

- **4.4 G3 — Spreads Macrofinanceiros (10 features)**
  - spread_selic_fed: teoria do carry trade — juros BR alto atrai capital estrangeiro
  - spread_10y_2y_us: inversão da curva como sinal de recessão americana
  - spread_ipca_cpi: diferencial de inflação → paridade de poder de compra (PPP)
  - fluxo_acum_21d/63d: oferta e demanda de dólares no mercado local

- **4.5 G4 — Retornos Externos (16 features)**
  - DXY: força global do USD em 6 moedas — se DXY sobe, BRL tende a cair
  - VIX: aversão a risco global — mercados EM sofrem em risk-off
  - Petróleo/minério/soja: termos de troca do Brasil
  - Ibovespa: risco-país local (proxy de CDS)
  - erro_focus: desvio entre expectativa Focus e spot

- **4.6 G5 — Calendário (8 features)**
  - dia_semana, mes, fim_de_mes, mes_copom, mes_fomc
  - Sazonalidade intraday/intramês em câmbio

- **Tabela resumo:** 5 grupos × features × cobertura

### Capítulo 5 — Estratégia de Validação

- **5.1 Por que walk-forward e não cross-validation aleatório?**
  - Séries temporais têm dependência temporal — leakage se dividir aleatoriamente
  - Diagrama visual do sliding_window: lookback 756 obs (~3 anos), step 63 (~1 trim), 39 folds
  - Por que janela fixa (sliding) em vez de expansiva: regime-breaks (COVID, eleições)

- **5.2 Split 80/20 temporal**
  - Train+Val: 3.242 obs (2010–out/2022), Test: 810 obs (nov/2022–fev/2026)
  - "One touch rule" para o test set — decisão de modelagem baseada APENAS no CV

### Capítulo 6 — Modelos: Família, Teoria e Escolha

- **6.1 Baseline obrigatório: Random Walk**
  - Hipótese de mercado eficiente (EMH): preço hoje incorpora toda informação disponível
  - RMSE benchmark: 0.0209 (D+5), 0.0519 (D+30), 0.0863 (D+90)
  - Por que é difícil bater: 80% dos gestores ativos não superam o índice de longo prazo

- **6.2 ARIMA (autocorrelação temporal)**
  - Teoria: Box-Jenkins, AR(p) captura autocorrelação, MA(q) captura choques passados
  - auto.arima: por que funciona em D+5 (ACF presente) e falha em D+30/D+90
  - RMSE: 0.0157 (D+5 **vence**), 0.0614 (D+30 **perde**), 0.100 (D+90 **perde**)

- **6.3 Ridge Regression**
  - Teoria: OLS com penalidade L2 → encolhe coeficientes → reduz overfitting
  - Quando funciona: preditores correlacionados, mais features que amostras
  - Resultado: não venceu em nenhum horizonte — sinal linear é fraco

- **6.4 Elastic Net (champion D+5)**
  - Combina L1 (seleção de features = LASSO) + L2 (estabilidade = Ridge)
  - Parâmetro mixture: 0=Ridge, 1=LASSO, 0.5=ElasticNet
  - Por que vence em D+5: seleciona poucos sinais relevantes no ruído de curto prazo

- **6.5 Random Forest (champion D+30)**
  - Teoria: ensemble de árvores decorrelacionadas (bagging + seleção aleatória de features)
  - Vantagens: captura não-linearidades, interações, robusto a outliers
  - Parâmetros-chave: mtry (features por árvore), min_n (tamanho mínimo do nó), trees=500
  - Por que vence em D+30: relações não-lineares entre fundamentos e câmbio médio prazo

- **6.6 XGBoost (champion D+90)**
  - Teoria: gradient boosting — cada árvore corrige os erros da anterior
  - Diferença do Random Forest: sequencial vs paralelo, boosting vs bagging
  - Parâmetros-chave: learn_rate, tree_depth, min_n, mtry
  - Por que vence em D+90: captura interações complexas de variáveis macro

- **6.7 Tabela comparativa completa (baseline CV)**
  - 6×3 tabela: modelo × horizonte × RMSE
  - Plot `outputs/figures/baseline-comparison-full.png`

### Capítulo 7 — Hyperparameter Tuning

- **7.1 Latin Hypercube Sampling**
  - Teoria: mais eficiente que grid search — cobre o espaço de forma uniforme
  - 30 configurações por modelo × 39 folds = 1.170 fits por modelo-horizonte
  - Espaços de busca: enet (penalty, mixture), rf (mtry, min_n), xgb (tree_depth, min_n, learn_rate, mtry)

- **7.2 Resultados do tuning**
  - Tabela: RMSE baseline vs RMSE tuned por modelo × horizonte
  - Plot `outputs/figures/tuning-comparison.png`
  - Observação: ganho marginal — modelos já eram bons com defaults

- **7.3 Champions por horizonte**
  - D+5: Elastic Net (RMSE=0.0209)
  - D+30: Random Forest (RMSE=0.0497)
  - D+90: XGBoost (RMSE=0.0688)

### Capítulo 8 — Avaliação Final no Test Set

- **8.1 Métricas numéricas (seção 9.1 do briefing)**
  - Tabela: horizonte × champion × Test RMSE × CV RMSE × diff%
  - Plot `outputs/figures/eval-pred-vs-actual.png`
  - Insight: test RMSE < CV RMSE em todos os casos → período de teste (2022-2026) foi menos
    volátil que o período de treino (2010-2022, que inclui COVID/2020)

- **8.2 Acurácia direcional (seção 9.2 do briefing)**
  - D+5: 49,3% — coin flip (consistente com EMH)
  - D+30: **61,0%** — melhor resultado
  - D+90: 58,4%
  - Discussão: acurácia acima de 55% já tem valor econômico

- **8.3 Valor econômico (seção 9.3 do briefing)**
  - Plot `outputs/figures/eval-strategy-returns.png`
  - D+5: -15,6% (igual ao buy-and-hold — sem valor)
  - D+30: **+5.940%** vs -51% buy-and-hold → **transformacional**
  - D+90: +1.505.861% vs -95% buy-and-hold
  - **Aviso crítico:** sem custos de transação — resultado teórico

- **8.4 Resíduos no tempo**
  - Plot `outputs/figures/eval-residuals-time.png`
  - Análise de regime-breaks: resíduos sistemáticos em períodos de estresse?

- **8.5 Importância de features (VIP)**
  - Plot `outputs/figures/vip-target_30d.png` (existe)
  - Interpretação: quais variáveis deram sinal real

### Capítulo 9 — Comparação e Análise Crítica dos Modelos

- Tabela geral unificada: todos os modelos × todos os horizontes × CV RMSE × Test RMSE × dir_accuracy
- Vantagens e desvantagens de cada modelo:
  - ARIMA: interpretável, excelente em D+5, não escala para features externas
  - Elastic Net: simples, estável, interpretável (coeficientes), fraco em não-linearidade
  - Random Forest: robusto, sem necessidade de normalização, caixa-preta
  - XGBoost: estado da arte tabular, mais hiperparâmetros, mais riscos de overfitting
- Quando usar cada um: regimes calmos vs estresse, D+5 vs D+90

### Capítulo 10 — Recomendações de Uso

- **Para trading/treasury:**
  - D+30 com RF: único horizonte com valor econômico real
  - Cuidados: sem leverage, custos de transação reduzem muito o retorno
  - Revisão periódica: modelos devem ser re-treinados

- **Para planejamento macro/corporativo:**
  - D+90 com XGBoost: sinal direcional (58%) para hedging de médio prazo
  - Não usar como previsão pontual — usar como cenário direcional

- **Limitações importantes:**
  - Sem dados textuais (notícias, sentimento) — potencial melhoria
  - Dataset começa em 2010 — regime pré-2010 não representado
  - Período de test (2022-2026) relativamente calmo → performance real pode ser pior
  - Previsão probabilística (P10/P50/P90) não implementada ainda

- **Próximos passos:**
  - ARIMAX para D+5 (adicionar features ao ARIMA)
  - Ensemble: combinar ElasticNet + RF + XGBoost
  - Previsão probabilística com quantile regression forest
  - Monitoramento contínuo de drift

---

## Assets disponíveis

**Figuras:**
- `outputs/figures/eda-01-usd-brl-ptax.png` ✅
- `outputs/figures/eda-02-retornos-diarios.png` ✅
- `outputs/figures/eda-03-dist-targets.png` ✅
- `outputs/figures/eda-04-boxplot-targets.png` ✅
- `outputs/figures/eda-05-missing-vars.png` ✅
- `outputs/figures/eda-06-cor-features-target30d.png` ✅
- `outputs/figures/eda-07-corrplot-mercado.png` ✅
- `outputs/figures/eda-08-volatilidade-usdbrl.png` ✅
- `outputs/figures/eda-09-focus-vs-ptax.png` ✅
- `outputs/figures/eda-10-focus-vs-target30d.png` ✅
- `outputs/figures/eda-11-acf-targets.png` ✅
- `outputs/figures/baseline-comparison.png` ✅
- `outputs/figures/baseline-comparison-full.png` ✅
- `outputs/figures/tuning-comparison.png` ✅
- `outputs/figures/eval-pred-vs-actual.png` ✅
- `outputs/figures/eval-residuals-time.png` ✅
- `outputs/figures/eval-strategy-returns.png` ✅
- `outputs/figures/vip-target_30d.png` ✅

**Tabelas CSV (para datatable interativo):**
- `outputs/tables/eda-target-stats.csv` ✅
- `outputs/tables/eda-top-correlacoes.csv` ✅
- `outputs/tables/eda-alta-correlacao.csv` ✅
- `outputs/tables/fe-feature-completude.csv` ✅
- `outputs/tables/fe-correlation-features.csv` ✅
- `outputs/tables/baseline-cv-results-full.csv` ✅
- `outputs/tables/tuning-results.csv` ✅
- `outputs/tables/test-performance.csv` ✅
- `outputs/tables/test-predictions.csv` ✅

---

## Decisões de implementação

1. **Língua:** português (pt-BR) — `lang: pt`
2. **Gráficos:** preferir plotly interativo (já usado no eda-overview.qmd como referência)
3. **Tabelas:** DT (`datatable`) para interatividade
4. **Educacional:** cada conceito técnico acompanhado de parágrafos explicativos — "por que isso importa?"
5. **Código:** `code-fold: true` — código visível para o leitor técnico que quiser
6. **Setup chunk:** carrega todos os CSVs e datasets necessários
7. **Tamanho estimado:** 600–900 linhas de Quarto (~30+ páginas renderizadas)
8. **VIP para target_5d e target_90d:** apenas vip-target_30d existe em disco —
   para D+5 e D+90, recalcular inline a partir dos modelos ou usar texto descritivo
9. **Callouts:** usar `.callout-note`, `.callout-warning`, `.callout-important` para highlights

---

## Restrições

- Não explicar a ingestão de dados (coleta via pacotes R)
- Incluir o modelo de dados de entrada (estrutura do dataset, variáveis, leakage)
- Tom educacional: cada seção deve poder ser lida por alguém aprendendo Data Science

---

## Estimativa de esforço

- 1 arquivo Quarto com ~700-1000 linhas
- ~10 capítulos, ~40 seções
- Renderizável com `quarto render reports/technical-report.qmd`
