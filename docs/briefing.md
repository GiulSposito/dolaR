Abaixo está uma abordagem pragmática para construir modelos de previsão do **preço do dólar/real**, por exemplo USD/BRL, para horizontes de **5, 30 e 90 dias** usando técnicas de data science.

## 1. Definir bem o problema

Antes do modelo, é importante definir exatamente o que será previsto:

**Variável-alvo:**

Preço futuro do dólar em reais, por exemplo:

```text
USD/BRL fechamento em D+5
USD/BRL fechamento em D+30
USD/BRL fechamento em D+90
```

Ou, preferencialmente, prever o **retorno** em vez do preço bruto:

```text
retorno_5d  = (preço_D+5  / preço_D) - 1
retorno_30d = (preço_D+30 / preço_D) - 1
retorno_90d = (preço_D+90 / preço_D) - 1
```

Prever retorno costuma ser melhor do que prever preço, porque a série de preços é normalmente não estacionária.

---

# 2. Estratégia geral

Eu usaria uma arquitetura com **três horizontes de previsão**, cada um com seu próprio modelo:

| Horizonte |    Objetivo | Característica                                                         |
| --------- | ----------: | ---------------------------------------------------------------------- |
| 5 dias    | Curto prazo | Mais influenciado por momentum, volatilidade, fluxo e ruído de mercado |
| 30 dias   | Médio prazo | Combina tendência, juros, risco-país, commodities e expectativas       |
| 90 dias   | Macro prazo | Mais influenciado por fundamentos macroeconômicos e cenário externo    |

A hipótese principal é que **o que explica o dólar em 5 dias não é exatamente o mesmo que explica o dólar em 90 dias**.

---

# 3. Coleta de dados

## 3.1 Dados de mercado

Fontes úteis:

| Variável                | Exemplo                                         |
| ----------------------- | ----------------------------------------------- |
| USD/BRL spot            | PTAX, fechamento diário, intraday se disponível |
| DXY                     | Índice global do dólar                          |
| Juros EUA               | Treasury 2Y, 10Y                                |
| Juros Brasil            | DI futuro, Selic, curva de juros                |
| Ibovespa                | Apetite a risco local                           |
| S&P 500 / Nasdaq        | Apetite a risco global                          |
| VIX                     | Medida de aversão a risco                       |
| Petróleo                | Brent ou WTI                                    |
| Minério de ferro        | Relevante para Brasil                           |
| CDS Brasil              | Risco-país                                      |
| EMBI+ Brasil            | Risco soberano                                  |
| Fluxo cambial           | Entrada/saída de dólares                        |
| Reservas internacionais | Fundamento macro                                |
| Balança comercial       | Exportações/importações                         |
| Conta corrente          | Pressão estrutural sobre câmbio                 |

## 3.2 Dados macroeconômicos

| Variável             | Uso                          |
| -------------------- | ---------------------------- |
| Inflação Brasil/IPCA | Pressão sobre juros e câmbio |
| Inflação EUA/CPI     | Política monetária americana |
| Selic                | Diferencial de juros         |
| Fed Funds Rate       | Juros EUA                    |
| PIB Brasil/EUA       | Ciclo econômico              |
| Expectativas Focus   | Selic, inflação, câmbio      |
| Resultado fiscal     | Percepção de risco           |
| Dívida/PIB           | Risco fiscal                 |

## 3.3 Dados alternativos

Pode-se enriquecer o modelo com:

| Fonte                 | Exemplo                                           |
| --------------------- | ------------------------------------------------- |
| Notícias              | Sentimento sobre Brasil, Fed, fiscal, commodities |
| Redes sociais         | Sentimento político/econômico                     |
| Calendário econômico  | FOMC, Copom, payroll, IPCA, CPI                   |
| Relatórios de mercado | Tom hawkish/dovish, risco fiscal                  |
| Google Trends         | Busca por “dólar hoje”, “crise fiscal”, etc.      |

---

# 4. Preparação da base

A base precisa estar estruturada como uma série temporal diária.

Exemplo:

| data | usd_brl | dxy | vix | juros_br | juros_us | cds_br | ibov | petróleo | target_5d | target_30d | target_90d |
| ---- | ------: | --: | --: | -------: | -------: | -----: | ---: | -------: | --------: | ---------: | ---------: |

Para cada data `t`, cria-se o alvo futuro:

```text
target_5d  = retorno do dólar entre t e t+5
target_30d = retorno do dólar entre t e t+30
target_90d = retorno do dólar entre t e t+90
```

Esse cuidado evita vazamento de informação.

---

# 5. Engenharia de atributos

Essa é provavelmente a parte mais importante.

## 5.1 Atributos do próprio dólar

| Feature                | Exemplo                            |
| ---------------------- | ---------------------------------- |
| Retornos passados      | 1d, 5d, 10d, 21d, 63d              |
| Médias móveis          | MM5, MM21, MM63                    |
| Distância da média     | preço atual / MM21 - 1             |
| Volatilidade realizada | std dos retornos em 5, 21, 63 dias |
| Momentum               | retorno acumulado recente          |
| Drawdown               | queda desde máxima recente         |
| RSI/MACD               | Indicadores técnicos, com cautela  |

## 5.2 Atributos macrofinanceiros

| Feature                         | Intuição                       |
| ------------------------------- | ------------------------------ |
| Diferencial de juros BR x EUA   | Carrego/carry trade            |
| Inclinação da curva de juros BR | Percepção fiscal/inflacionária |
| Inclinação da curva EUA         | Política monetária americana   |
| DXY retorno 5/21 dias           | Força global do dólar          |
| VIX nível e variação            | Aversão a risco                |
| CDS Brasil nível e variação     | Risco-país                     |
| Ibovespa retorno                | Apetite a risco local          |
| Petróleo/minério                | Termos de troca                |
| Fluxo cambial acumulado         | Pressão de oferta/demanda      |

## 5.3 Features de calendário

| Feature                    | Exemplo                     |
| -------------------------- | --------------------------- |
| Dia da semana              | segunda, terça etc.         |
| Mês                        | sazonalidade                |
| Fim de mês                 | fechamento de posições      |
| Semana de Copom/FOMC       | eventos monetários          |
| Semana de payroll/CPI/IPCA | eventos de inflação/emprego |
| Eleição ou evento fiscal   | variável dummy              |

## 5.4 Features textuais

Para notícias, pode-se usar NLP:

| Técnica               | Saída                                            |
| --------------------- | ------------------------------------------------ |
| Sentiment analysis    | sentimento positivo/negativo                     |
| Classificação de tema | fiscal, Fed, China, commodities                  |
| Embeddings            | vetor semântico das notícias                     |
| Contagem de termos    | “risco fiscal”, “inflação”, “Fed”, “dólar forte” |

Essas variáveis podem ser agregadas por dia:

```text
sentimento_medio_dia
volume_noticias_risco_fiscal
sentimento_fed
sentimento_brasil
```

---

# 6. Modelos candidatos

Eu montaria uma esteira com diferentes famílias de modelos.

## 6.1 Baselines obrigatórios

Antes de usar modelos sofisticados, é essencial comparar contra modelos simples:

| Modelo          | Descrição                                    |
| --------------- | -------------------------------------------- |
| Random Walk     | preço futuro = preço atual                   |
| Média histórica | retorno futuro = média dos retornos passados |
| ARIMA/SARIMA    | modelo estatístico clássico                  |
| EWMA            | média móvel exponencial                      |
| Carry simples   | baseado no diferencial de juros              |

No câmbio, é comum modelos complexos perderem para random walk em alguns horizontes. Por isso o baseline é crítico.

---

## 6.2 Modelos estatísticos

| Modelo  | Uso                                            |
| ------- | ---------------------------------------------- |
| ARIMA   | Autocorrelação da série                        |
| ARIMAX  | ARIMA com variáveis externas                   |
| VAR     | Relação entre dólar, juros, bolsa, commodities |
| GARCH   | Previsão de volatilidade                       |
| Prophet | Tendência/sazonalidade, com cuidado            |

Exemplo:

```text
USD/BRL ~ DXY + VIX + CDS + diferencial de juros + commodities
```

---

## 6.3 Machine Learning tabular

Para uma primeira versão robusta, eu priorizaria:

| Modelo                     | Uso                        |
| -------------------------- | -------------------------- |
| Ridge/Lasso/Elastic Net    | Benchmark interpretável    |
| Random Forest              | Não linearidade            |
| XGBoost/LightGBM/CatBoost  | Forte para dados tabulares |
| Quantile Regression Forest | Intervalos de previsão     |
| Gradient Boosting Quantile | Cenários p10/p50/p90       |

Minha escolha inicial seria:

```text
LightGBM ou XGBoost com validação temporal
```

Por quê?

Porque câmbio depende de várias relações não lineares, interações e regimes de mercado. Boosting costuma funcionar bem em dados tabulares com features macrofinanceiras.

---

## 6.4 Deep Learning

Só usaria depois de ter uma base forte.

| Modelo                      | Uso                                   |
| --------------------------- | ------------------------------------- |
| LSTM/GRU                    | Sequências temporais                  |
| Temporal CNN                | Padrões locais na série               |
| Temporal Fusion Transformer | Multivariáveis e horizontes múltiplos |
| N-BEATS / N-HiTS            | Forecasting moderno                   |
| DeepAR                      | Distribuição de previsão              |
| Transformers temporais      | Relações complexas                    |

Atenção: deep learning pode ser overkill se a base tiver poucos anos de dados diários. Para USD/BRL, uma base diária de 10 anos tem cerca de 2.500 observações úteis, o que é pouco para redes muito complexas.

---

# 7. Três estratégias de modelagem

## Estratégia A — um modelo por horizonte

Criar três modelos separados:

```text
modelo_5d  → prevê retorno em 5 dias
modelo_30d → prevê retorno em 30 dias
modelo_90d → prevê retorno em 90 dias
```

Vantagem: simples, interpretável, fácil de comparar.

Eu começaria por essa.

---

## Estratégia B — modelo multi-horizonte

Um único modelo prevê vários horizontes:

```text
entrada: dados até hoje
saída: retorno_5d, retorno_30d, retorno_90d
```

Modelos possíveis:

```text
MultiOutputRegressor
Temporal Fusion Transformer
N-BEATS/N-HiTS
Seq2Seq
```

Vantagem: pode aprender relações entre horizontes.

---

## Estratégia C — previsão probabilística

Em vez de prever apenas um número, prever uma distribuição:

```text
P10: cenário otimista para real
P50: cenário central
P90: cenário de estresse
```

Exemplo de saída:

| Horizonte |  P10 |  P50 |  P90 |
| --------- | ---: | ---: | ---: |
| 5 dias    | 5,37 | 5,43 | 5,52 |
| 30 dias   | 5,25 | 5,48 | 5,79 |
| 90 dias   | 5,10 | 5,55 | 6,10 |

Essa abordagem é mais útil para tomada de decisão, porque câmbio é altamente incerto.

---

# 8. Validação correta

Não se deve usar validação aleatória, porque isso vaza informação temporal.

O ideal é usar **walk-forward validation**.

Exemplo:

```text
Treina: 2015–2019
Testa: 2020

Treina: 2015–2020
Testa: 2021

Treina: 2015–2021
Testa: 2022

Treina: 2015–2022
Testa: 2023
```

Ou janelas móveis:

```text
Treina últimos 3 anos
Testa próximos 3 meses
```

Para os horizontes de 30 e 90 dias, é preciso tomar cuidado com sobreposição de targets. Muitas observações ficam correlacionadas entre si.

---

# 9. Métricas de avaliação

Eu avaliaria em três dimensões.

## 9.1 Erro numérico

| Métrica         | Uso                      |
| --------------- | ------------------------ |
| MAE             | Erro médio absoluto      |
| RMSE            | Penaliza erros grandes   |
| MAPE            | Percentual, com cuidado  |
| sMAPE           | Alternativa mais estável |
| MAE em centavos | Fácil de comunicar       |

Exemplo:

```text
Erro médio em D+5 = R$ 0,04
Erro médio em D+30 = R$ 0,13
Erro médio em D+90 = R$ 0,25
```

## 9.2 Direção do movimento

Muito importante para câmbio:

```text
O modelo acertou se o dólar sobe ou cai?
```

Métricas:

| Métrica              | Uso                                     |
| -------------------- | --------------------------------------- |
| Directional Accuracy | % de acerto de direção                  |
| Precision para alta  | Quando prevê alta, quantas vezes acerta |
| Recall de alta       | Quantas altas reais ele captura         |
| Matriz de confusão   | Alta, queda, estável                    |

## 9.3 Valor econômico

A métrica mais importante pode ser econômica:

```text
Uma estratégia baseada no modelo ganha dinheiro?
```

Exemplos:

| Métrica            | Uso                          |
| ------------------ | ---------------------------- |
| Retorno acumulado  | Performance da estratégia    |
| Sharpe Ratio       | Retorno ajustado a risco     |
| Max Drawdown       | Perda máxima                 |
| Turnover           | Frequência de troca          |
| Custo de transação | Spread, corretagem, slippage |
| Hit ratio          | Taxa de acerto operacional   |

---

# 10. Feature importance e explicabilidade

Para modelos como XGBoost/LightGBM, usar:

```text
SHAP values
Permutation importance
Partial dependence plots
```

Isso ajuda a responder:

```text
Por que o modelo está prevendo alta do dólar?
```

Exemplo de explicação:

| Fator                                  | Efeito                      |
| -------------------------------------- | --------------------------- |
| Alta do DXY                            | Pressiona USD/BRL para cima |
| Aumento do VIX                         | Pressiona dólar para cima   |
| Queda do diferencial de juros BR x EUA | Reduz atratividade do real  |
| Alta do CDS Brasil                     | Pressiona dólar para cima   |
| Alta do minério                        | Pode favorecer real         |

---

# 11. Tratamento de regimes

O dólar muda de comportamento conforme o regime de mercado.

Exemplos de regimes:

| Regime                | Característica                           |
| --------------------- | ---------------------------------------- |
| Risk-on global        | Bolsa sobe, VIX cai, real aprecia        |
| Risk-off global       | VIX sobe, dólar forte, emergentes sofrem |
| Crise fiscal Brasil   | CDS sobe, curva abre, real deprecia      |
| Carry favorável       | Juros BR altos atraem capital            |
| Dólar global forte    | DXY domina movimentos locais             |
| Choque de commodities | Termos de troca afetam Brasil            |

Uma abordagem boa é criar um classificador de regime:

```text
regime = clustering(VIX, DXY, CDS, juros, Ibovespa, commodities)
```

Depois:

```text
modelo específico por regime
```

Ou incluir o regime como feature no modelo principal.

---

# 12. Arquitetura de referência

Uma arquitetura simples poderia ser:

```text
[Coleta de dados]
    ↓
[Data Lake / Banco histórico]
    ↓
[Feature Store]
    ↓
[Modelos por horizonte]
    ├── Modelo 5 dias
    ├── Modelo 30 dias
    └── Modelo 90 dias
    ↓
[Forecast probabilístico]
    ↓
[Explicabilidade / SHAP]
    ↓
[Dashboard / API]
```

Saída esperada:

```text
Hoje: 2026-07-02
USD/BRL atual: 5,45

Previsão D+5:
- Central: 5,49
- Intervalo 80%: 5,37 a 5,62
- Direção esperada: alta moderada
- Principais fatores: DXY forte, VIX em alta, CDS Brasil subindo

Previsão D+30:
- Central: 5,57
- Intervalo 80%: 5,25 a 5,90

Previsão D+90:
- Central: 5,70
- Intervalo 80%: 5,10 a 6,35
```

---

# 13. MVP recomendado

Eu faria o MVP em quatro etapas.

## Etapa 1 — Dataset e baseline

Construir base diária com:

```text
USD/BRL
DXY
VIX
S&P 500
Ibovespa
DI/Selic
Treasury 10Y
CDS Brasil
Petróleo
Minério
```

Criar targets:

```text
retorno_5d
retorno_30d
retorno_90d
```

Rodar baselines:

```text
Random Walk
ARIMA
Regressão linear
Ridge
```

---

## Etapa 2 — Modelo ML tabular

Treinar:

```text
XGBoost ou LightGBM
```

Com features:

```text
lags
médias móveis
volatilidade
retornos acumulados
diferencial de juros
DXY
VIX
CDS
commodities
```

Validar com walk-forward.

---

## Etapa 3 — Previsão probabilística

Adicionar previsão por quantis:

```text
P10
P50
P90
```

Isso permite gerar cenários:

```text
cenário favorável ao real
cenário central
cenário de estresse
```

---

## Etapa 4 — Explicabilidade e dashboard

Dashboard com:

| Bloco      | Conteúdo                                    |
| ---------- | ------------------------------------------- |
| Previsão   | D+5, D+30, D+90                             |
| Intervalo  | P10, P50, P90                               |
| Direção    | Alta, queda, estável                        |
| Confiança  | Baixa, média, alta                          |
| Explicação | Top 5 fatores via SHAP                      |
| Histórico  | Erro recente do modelo                      |
| Alerta     | Eventos próximos: Copom, FOMC, CPI, payroll |


# 15. Cuidados importantes

## 15.1 Câmbio é difícil de prever

O dólar é uma das séries financeiras mais difíceis de prever. Em vários períodos, o melhor modelo pode ser simplesmente:

```text
dólar amanhã = dólar hoje
```

Por isso, o modelo deve ser avaliado contra random walk.

## 15.2 Não confundir previsão com cenário

Para 90 dias, talvez seja melhor falar em **cenários probabilísticos** do que em previsão pontual.

Exemplo:

```text
Cenário central: dólar entre 5,40 e 5,70
Cenário de estresse: dólar acima de 5,90
Cenário benigno: dólar abaixo de 5,25
```

## 15.3 Evitar vazamento de informação

Exemplos de vazamento:

```text
Usar dado macro divulgado depois da data prevista
Usar revisão histórica de indicador como se estivesse disponível no passado
Usar target sobreposto sem cuidado
Normalizar a série usando estatísticas do futuro
```

## 15.4 Cuidar com datas de divulgação

Indicadores macro têm datas específicas de publicação.

Exemplo:

```text
IPCA de junho pode ser divulgado só em julho.
```

No dataset, a variável só deve aparecer a partir da data em que ficou conhecida pelo mercado.

---

# 16. Recomendação final

A melhor abordagem seria:

```text
1. Começar com previsão de retornos, não preços.
2. Criar três modelos separados: 5, 30 e 90 dias.
3. Usar random walk como baseline obrigatório.
4. Construir features de mercado, macro, risco e commodities.
5. Treinar modelos XGBoost/LightGBM com validação walk-forward.
6. Evoluir para previsão probabilística com P10/P50/P90.
7. Usar SHAP para explicar os principais fatores da previsão.
8. Monitorar erro, estabilidade e valor econômico ao longo do tempo.
```

Em termos de MVP, eu começaria com:

```text
Random Walk + Ridge + XGBoost/LightGBM
```

E só depois avaliaria modelos mais sofisticados como LSTM, Temporal Fusion Transformer ou N-BEATS.
