Abaixo está uma lista prática de **fontes de dados na internet** para montar uma esteira de modelos de previsão do **USD/BRL para 5, 30 e 90 dias**. Eu separaria em três grupos:

1. **fontes essenciais para o MVP**
2. **fontes complementares para melhorar o modelo**
3. **fontes alternativas/comerciais ou que exigem scraping/licença**

---

# 1. Fontes essenciais para o MVP

## 1. Banco Central do Brasil — PTAX / câmbio oficial

**Uso no modelo:** variável-alvo principal, ou benchmark oficial do USD/BRL.

O Banco Central disponibiliza a API PTAX via OData, com recursos como `CotacaoDolarDia`, `CotacaoDolarPeriodo`, `CotacaoMoedaDia` e `CotacaoMoedaPeriodo`. A própria documentação do BCB informa que os retornos podem vir em JSON, XML, CSV ou HTML. ([Portal de Dados Abertos do Banco Central][1])

**Tipo de acesso:** API OData / JSON / CSV.

**Exemplo de uso:**

```python
import requests
import pandas as pd

url = (
    "https://olinda.bcb.gov.br/olinda/servico/PTAX/versao/v1/odata/"
    "CotacaoDolarPeriodo(dataInicial=@dataInicial,dataFinalCotacao=@dataFinalCotacao)"
    "?@dataInicial='01-01-2020'"
    "&@dataFinalCotacao='12-31-2024'"
    "&$format=json"
)

data = requests.get(url).json()["value"]
df = pd.DataFrame(data)
```

**Variáveis úteis:**

| Variável          | Uso                                         |
| ----------------- | ------------------------------------------- |
| cotação compra    | proxy de USD/BRL                            |
| cotação venda     | proxy de USD/BRL                            |
| data/hora cotação | controle temporal                           |
| moeda             | permite expandir para EUR/BRL, GBP/BRL etc. |

---

## 2. Banco Central do Brasil — SGS

**Uso no modelo:** Selic, inflação, câmbio, agregados monetários, atividade, crédito, risco macro local.

O SGS é o sistema de séries temporais do Banco Central. A API JSON usa o padrão `bcdata.sgs.{codigo_serie}` e permite informar `dataInicial` e `dataFinal`. ([Portal de Dados Abertos do Banco Central][2])

**Tipo de acesso:** API REST / JSON.

**Exemplo:**

```python
import requests
import pandas as pd

codigo_serie = 432  # exemplo: meta Selic
url = (
    f"https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo_serie}/dados"
    "?formato=json&dataInicial=01/01/2020&dataFinal=31/12/2024"
)

df = pd.DataFrame(requests.get(url).json())
df["data"] = pd.to_datetime(df["data"], dayfirst=True)
df["valor"] = pd.to_numeric(df["valor"])
```

**Variáveis úteis:**

| Grupo         | Exemplos                                                         |
| ------------- | ---------------------------------------------------------------- |
| Juros         | Selic, meta Selic, CDI                                           |
| Inflação      | IPCA, IGP-M, INPC                                                |
| Câmbio        | séries históricas de câmbio                                      |
| Crédito       | saldo de crédito, concessões                                     |
| Atividade     | indicadores econômicos diversos                                  |
| Setor externo | reservas, balanço de pagamentos, fluxo cambial quando disponível |

**Biblioteca útil:** `python-bcb`, que encapsula SGS, PTAX e expectativas. ([Wilson Freitas][3])

```bash
pip install python-bcb
```

```python
from bcb import sgs

df = sgs.get({"selic_meta": 432}, start="2020-01-01")
```

---

## 3. Banco Central do Brasil — Expectativas Focus

**Uso no modelo:** expectativas de mercado para câmbio, Selic, IPCA, PIB, fiscal e balança comercial.

O Focus resume estatísticas de expectativas coletadas pelo Banco Central junto ao mercado e é divulgado semanalmente. ([Banco Central do Brasil][4]) A API de expectativas está disponível via OData/Swagger no portal de dados abertos do BCB. ([Portal de Dados Abertos do Banco Central][5])

**Tipo de acesso:** API OData / JSON.

**Variáveis úteis:**

| Variável                         | Uso                                |
| -------------------------------- | ---------------------------------- |
| Expectativa de câmbio fim de ano | forte benchmark                    |
| Expectativa Selic                | política monetária esperada        |
| Expectativa IPCA                 | inflação esperada                  |
| Expectativa PIB                  | ciclo doméstico                    |
| Expectativa balança comercial    | setor externo                      |
| Mediana / média / desvio-padrão  | nível e dispersão das expectativas |

**Uso recomendado no modelo:**

```text
focus_cambio_ano
focus_selic_ano
focus_ipca_ano
focus_pib_ano
focus_cambio_12m
dispersao_expectativas_cambio
revisao_focus_1s
revisao_focus_4s
```

---

## 4. FRED — Federal Reserve Economic Data

**Uso no modelo:** juros americanos, inflação EUA, Fed Funds, VIX, Treasury yields, dólar global, atividade econômica americana.

O FRED é uma das melhores fontes gratuitas para séries macroeconômicas e financeiras dos EUA. Ele informa disponibilizar mais de 845 mil séries de 121 fontes, e possui API para recuperar observações históricas em JSON ou XML. ([FRED][6])

**Tipo de acesso:** API REST / JSON / CSV.

**Exemplo:**

```python
import requests
import pandas as pd

api_key = "SUA_CHAVE_FRED"
series_id = "DGS10"  # Treasury 10Y

url = (
    "https://api.stlouisfed.org/fred/series/observations"
    f"?series_id={series_id}&api_key={api_key}&file_type=json"
)

data = requests.get(url).json()["observations"]
df = pd.DataFrame(data)
```

**Séries úteis para USD/BRL:**

| Série                   | Descrição                                             |
| ----------------------- | ----------------------------------------------------- |
| `DGS2`                  | Treasury 2 anos                                       |
| `DGS10`                 | Treasury 10 anos                                      |
| `FEDFUNDS`              | Fed Funds Rate                                        |
| `SOFR`                  | Secured Overnight Financing Rate                      |
| `CPIAUCSL`              | CPI EUA                                               |
| `PCEPI`                 | PCE Price Index                                       |
| `UNRATE`                | Desemprego EUA                                        |
| `VIXCLS`                | VIX via FRED                                          |
| `DTWEXBGS` ou similares | índice amplo do dólar, dependendo da série disponível |

O VIX também está disponível como série `VIXCLS` no FRED, com download histórico desde 1990. ([FRED][7])

---

## 5. Yahoo Finance / yfinance

**Uso no modelo:** séries de mercado globais: USD/BRL, DXY, VIX, S&P 500, Nasdaq, Ibovespa, ETFs, commodities via tickers.

`yfinance` é uma biblioteca open-source que acessa APIs públicas do Yahoo Finance, mas a própria documentação do projeto alerta que o uso é para pesquisa/educação e que os direitos de uso dos dados devem seguir os termos do Yahoo. ([GitHub][8])

**Tipo de acesso:** biblioteca Python / API não oficial.

**Exemplo:**

```bash
pip install yfinance
```

```python
import yfinance as yf

tickers = [
    "USDBRL=X",  # USD/BRL
    "DX-Y.NYB",  # DXY
    "^VIX",      # VIX
    "^GSPC",     # S&P 500
    "^BVSP",     # Ibovespa
    "CL=F",      # WTI
    "BZ=F",      # Brent
]

df = yf.download(tickers, start="2020-01-01", auto_adjust=True)["Close"]
```

**Variáveis úteis:**

| Ticker     | Variável |
| ---------- | -------- |
| `USDBRL=X` | USD/BRL  |
| `DX-Y.NYB` | DXY      |
| `^VIX`     | VIX      |
| `^GSPC`    | S&P 500  |
| `^IXIC`    | Nasdaq   |
| `^BVSP`    | Ibovespa |
| `CL=F`     | WTI      |
| `BZ=F`     | Brent    |
| `GC=F`     | Ouro     |
| `HG=F`     | Cobre    |

Eu usaria Yahoo/yfinance no MVP pela facilidade, mas substituiria por fontes oficiais ou pagas em produção.

---

# 2. Fontes brasileiras complementares

## 6. IBGE / SIDRA

**Uso no modelo:** inflação, atividade econômica, produção industrial, varejo, desemprego, contas nacionais.

O IBGE disponibiliza a API SIDRA com parâmetros para tabela, variável e período, entre outros filtros. ([API Sidra][9])

**Tipo de acesso:** API REST / JSON.

**Bibliotecas úteis:**

Python:

```bash
pip install sidrapy
```

```python
import sidrapy

df = sidrapy.get_table(
    table_code="1737",  # exemplo: IPCA
    territorial_level="1",
    ibge_territorial_code="all",
    period="last 24"
)
```

R:

```r
install.packages("sidra")
library(sidra)
```

**Variáveis úteis:**

| Tema          | Uso                 |
| ------------- | ------------------- |
| IPCA          | inflação realizada  |
| PMC           | varejo              |
| PIM-PF        | produção industrial |
| PNAD Contínua | mercado de trabalho |
| PIB           | atividade econômica |

Para previsão de 5 dias, esses dados entram pouco; para 30 e 90 dias, são mais relevantes.

---

## 7. Ipeadata

**Uso no modelo:** base macro consolidada, indicadores históricos, dados sociais e econômicos.

O Ipeadata tem uma API que disponibiliza metadados, valores das séries, temas e territórios. ([IPEADATA][10])

**Tipo de acesso:** API REST / OData / JSON.

**Exemplo conceitual:**

```python
import requests
import pandas as pd

serie = "BM12_TJOVER12"  # exemplo ilustrativo; validar código no Ipeadata
url = f"http://www.ipeadata.gov.br/api/odata4/ValoresSerie(SERCODIGO='{serie}')"

df = pd.DataFrame(requests.get(url).json()["value"])
```

**Variáveis úteis:**

| Grupo         | Exemplos                      |
| ------------- | ----------------------------- |
| Juros         | séries históricas             |
| Câmbio        | câmbio nominal/real           |
| Inflação      | índices diversos              |
| Fiscal        | dívida, resultado primário    |
| Atividade     | produção, PIB, emprego        |
| Setor externo | transações correntes, balança |

---

## 8. Tesouro Nacional / Tesouro Transparente

**Uso no modelo:** risco fiscal, dívida pública, resultado primário, indicadores fiscais.

O Tesouro Nacional disponibiliza APIs e dados abertos para informações produzidas ou consolidadas pela instituição. ([Serviços e Informações do Brasil][11])

**Tipo de acesso:** API / dados abertos / CKAN.

**Variáveis úteis:**

| Variável               | Uso                            |
| ---------------------- | ------------------------------ |
| Dívida Pública Federal | risco fiscal                   |
| Resultado primário     | percepção fiscal               |
| Resultado nominal      | pressão fiscal                 |
| Tesouro Direto         | curva de títulos públicos      |
| SICONFI                | finanças de entes subnacionais |

**Uso no modelo:**

```text
divida_pib
resultado_primario_12m
resultado_nominal_12m
estoque_divida_publica
participacao_posfixada
prazo_medio_divida
```

Essas variáveis são mais úteis no horizonte de 90 dias do que no de 5 dias.

---

## 9. Comex Stat / MDIC

**Uso no modelo:** balança comercial, exportações, importações, termos de troca, fluxo estrutural de dólar.

O Comex Stat é o sistema oficial para extração de estatísticas do comércio exterior brasileiro e permite consultas e extração em CSV/planilhas. ([Comex Stat][12]) O MDIC também disponibiliza bases brutas em CSV com os dados usados na construção da balança comercial. ([Serviços e Informações do Brasil][13])

**Tipo de acesso:** CSV / planilhas / consultas web / eventualmente pacotes comunitários.

**Variáveis úteis:**

| Variável                   | Uso                    |
| -------------------------- | ---------------------- |
| Exportações mensais        | oferta de dólar        |
| Importações mensais        | demanda de dólar       |
| Saldo comercial            | fundamento externo     |
| Exportação por produto     | commodities relevantes |
| Exportação para China      | exposição China/Brasil |
| Importação de combustíveis | pressão em dólar       |

**Uso no modelo:**

```text
saldo_comercial_12m
exportacoes_3m
importacoes_3m
exportacao_soja
exportacao_minerio
exportacao_petroleo
```

---

## 10. B3 — Market Data, índices, derivativos e dólar futuro

**Uso no modelo:** Ibovespa, contratos futuros de dólar, DI futuro, cupom cambial, volatilidade local, volume e posições.

A B3 possui área de dados históricos de market data e índices, incluindo cotações históricas, derivativos, ajustes do pregão e câmbio. ([B3][14]) Também disponibiliza APIs via B3 for Developers, embora nem todos os dados sejam necessariamente gratuitos ou simples de acessar. ([B3][15])

**Tipo de acesso:** arquivos históricos, downloads, APIs B3, algumas páginas com download manual.

**Variáveis úteis:**

| Variável            | Uso                          |
| ------------------- | ---------------------------- |
| Dólar futuro        | expectativa de mercado       |
| DI futuro           | curva de juros local         |
| Ibovespa            | risco local                  |
| Mini dólar          | liquidez e volume            |
| Ajuste diário       | preço oficial de derivativos |
| Volume financeiro   | pressão de mercado           |
| Contratos em aberto | posicionamento               |

**Observação:** para modelos de 5 dias, dados de dólar futuro e DI futuro podem ser muito relevantes.

---

## 11. ANBIMA

**Uso no modelo:** curva de juros brasileira, títulos públicos, inflação implícita, mercado secundário.

A ANBIMA disponibiliza uma API de títulos públicos que divulga curvas de juros zero-cupom soberanas, extraídas de taxas de títulos prefixados e IPCA+, além de inflação implícita; a periodicidade informada é diária. ([ANBIMA Developers][16])

**Tipo de acesso:** API / ANBIMA Data.

**Variáveis úteis:**

| Variável           | Uso                         |
| ------------------ | --------------------------- |
| Curva prefixada    | juros nominais Brasil       |
| Curva IPCA+        | juros reais Brasil          |
| Inflação implícita | expectativa de inflação     |
| Taxas NTN-B        | risco real/fiscal           |
| Taxas LTN/NTN-F    | política monetária esperada |

**Uso no modelo:**

```text
juros_br_1y
juros_br_2y
juros_br_5y
juros_real_5y
inflacao_implicita_5y
slope_br_5y_1y
```

---

# 3. Fontes internacionais complementares

## 12. CBOE — VIX oficial

**Uso no modelo:** aversão a risco global.

A CBOE disponibiliza dados históricos para o VIX e outros índices de volatilidade. ([Cboe Global Markets][17])

**Tipo de acesso:** CSV/download histórico ou via outros provedores.

**Alternativa mais simples:** usar FRED `VIXCLS` ou Yahoo `^VIX`.

**Variáveis úteis:**

| Variável           | Uso               |
| ------------------ | ----------------- |
| VIX nível          | risco global      |
| VIX variação 1d/5d | choque de risco   |
| VIX média 21d      | regime de risco   |
| VIX percentile     | stress de mercado |

---

## 13. EIA — petróleo, energia e estoques

**Uso no modelo:** Brent, WTI, estoques, energia global.

A U.S. Energy Information Administration oferece API aberta para dados de energia; a página de dados abertos da EIA informa API e documentação. ([EIA - Administração de Informação sobre Energia][18])

**Tipo de acesso:** API REST / JSON, geralmente com API key.

**Variáveis úteis:**

| Variável                 | Uso                 |
| ------------------------ | ------------------- |
| WTI spot                 | commodity global    |
| Brent spot               | termo de troca      |
| Estoques de petróleo EUA | choque de petróleo  |
| Produção EUA             | oferta global       |
| Gasolina/diesel          | inflação de energia |

**Exemplo conceitual:**

```python
import requests

api_key = "SUA_CHAVE_EIA"
url = "https://api.eia.gov/v2/petroleum/pri/spt/data/?api_key=" + api_key

data = requests.get(url).json()
```

---

## 14. World Bank — Commodities / Pink Sheet

**Uso no modelo:** commodities mensais: petróleo, minério, soja, metais, alimentos.

O Banco Mundial mantém a base “Commodity Markets / Pink Sheet”, com preços internacionais de commodities. ([Documentos Públicos][19])

**Tipo de acesso:** planilhas/arquivos de dados, periodicidade mensal.

**Variáveis úteis para Brasil:**

| Commodity        | Relevância                           |
| ---------------- | ------------------------------------ |
| Minério de ferro | exportações brasileiras              |
| Soja             | exportações brasileiras              |
| Petróleo Brent   | Petrobras, balança e inflação        |
| Açúcar           | agro                                 |
| Café             | agro                                 |
| Celulose         | relevante para empresas exportadoras |
| Cobre            | proxy de ciclo global                |

**Uso no modelo:** mais relevante para 30 e 90 dias.

---

## 15. Nasdaq Data Link

**Uso no modelo:** dados financeiros, macro, commodities e datasets alternativos.

A Nasdaq Data Link oferece APIs para dados financeiros e econômicos. A documentação informa acesso a datasets gratuitos e premium via API key. ([data.nasdaq.com][20])

**Tipo de acesso:** API REST / JSON / CSV.

**Variáveis úteis:**

| Grupo        | Exemplos                   |
| ------------ | -------------------------- |
| Commodities  | energia, metais, agrícolas |
| Mercado      | índices, taxas, futuros    |
| Macro        | alguns datasets econômicos |
| Alternativos | datasets premium           |

**Observação:** é uma boa opção para evoluir o modelo, mas muitos datasets relevantes podem ser pagos.

---

## 16. CME FedWatch

**Uso no modelo:** expectativas de juros dos EUA, probabilidade implícita de cortes/altas do Fed.

O CME FedWatch acompanha probabilidades de mudanças na taxa do Fed com base em preços de futuros de Fed Funds. ([CME Group][21]) A CME também oferece uma API FedWatch, mas como produto pago. ([CME Group][22])

**Tipo de acesso:** site / API paga.

**Variáveis úteis:**

| Variável                               | Uso                            |
| -------------------------------------- | ------------------------------ |
| Probabilidade de corte no FOMC próximo | expectativa Fed                |
| Probabilidade de alta                  | choque hawkish                 |
| Taxa esperada por reunião              | curva Fed implícita            |
| Mudança diária de probabilidade        | surpresa de política monetária |

**Alternativa gratuita:** derivar parcialmente expectativas usando Fed Funds futures via fontes de mercado, quando disponíveis.

---

# 4. Notícias, calendário econômico e sentimento

## 17. GDELT

**Uso no modelo:** notícias globais, volume de notícias, sentimento, eventos geopolíticos.

**Tipo de acesso:** API pública / arquivos.

**Variáveis úteis:**

| Variável                        | Uso                    |
| ------------------------------- | ---------------------- |
| volume de notícias sobre Brasil | risco local            |
| volume de notícias sobre fiscal | stress fiscal          |
| sentimento Brasil               | risco-país textual     |
| sentimento Fed                  | política monetária EUA |
| sentimento China                | commodities            |
| eventos geopolíticos            | risk-off               |

**Exemplo de features:**

```text
news_volume_brazil
news_sentiment_brazil
news_volume_fiscal
news_sentiment_fed
news_volume_china
```

---

## 18. NewsAPI, Event Registry, Google News via scraping controlado

**Uso no modelo:** sentimento e eventos de mercado.

**Tipo de acesso:** API comercial/freemium ou scraping com cuidado.

**Variáveis úteis:**

| Tema                  | Uso                   |
| --------------------- | --------------------- |
| “risco fiscal Brasil” | pressão local         |
| “Fed hawkish/dovish”  | dólar global          |
| “China stimulus”      | commodities           |
| “election Brazil”     | risco político        |
| “emerging markets”    | fluxo para emergentes |

**Cuidados:**

```text
1. Respeitar termos de uso.
2. Guardar apenas metadados se a licença não permitir armazenar texto integral.
3. Evitar scraping agressivo.
4. Registrar data/hora da publicação.
5. Evitar vazamento temporal: só usar notícia publicada até a data da previsão.
```

---

## 19. Calendário econômico

**Uso no modelo:** dummies de eventos que aumentam volatilidade.

Fontes possíveis:

| Fonte                | Acesso                       |
| -------------------- | ---------------------------- |
| Investing.com        | scraping, cuidado com termos |
| Trading Economics    | API paga/freemium            |
| ForexFactory         | scraping, cuidado com termos |
| Econoday             | comercial                    |
| Calendários oficiais | Fed, BCB, IBGE, BLS, BEA     |

**Eventos úteis:**

| Evento         | Variável         |
| -------------- | ---------------- |
| Copom          | `is_copom_week`  |
| FOMC           | `is_fomc_week`   |
| Payroll        | `is_payroll_day` |
| CPI EUA        | `is_us_cpi_day`  |
| IPCA Brasil    | `is_ipca_day`    |
| PIB Brasil/EUA | `is_gdp_release` |
| Focus          | `is_focus_day`   |

---

# 5. Fontes de risco-país, CDS e emergentes

## 20. CDS Brasil / EMBI+

**Uso no modelo:** risco soberano, percepção fiscal e risco de emergentes.

**Fontes possíveis:**

| Fonte               | Acesso                      |
| ------------------- | --------------------------- |
| JP Morgan EMBI+     | normalmente pago/licenciado |
| Investing.com       | web scraping, cuidado       |
| Refinitiv/Bloomberg | pago                        |
| FRED/Ipeadata/BCB   | verificar séries proxy      |
| Yahoo Finance       | alguns ETFs/proxies         |

**Proxies gratuitos úteis:**

| Proxy                                 | Uso                       |
| ------------------------------------- | ------------------------- |
| ETF `EWZ`                             | risco Brasil em dólar     |
| Spread Brasil via títulos             | risco soberano aproximado |
| Ibovespa em dólar                     | apetite por Brasil        |
| CDS se disponível em fonte aberta     | risco direto              |
| EMBI+ se disponível via série pública | risco emergente           |

---

# 6. APIs pagas ou freemium úteis

## 21. Alpha Vantage

**Uso:** câmbio, ações, indicadores técnicos.

**Tipo:** API gratuita limitada + planos pagos.

**Pode fornecer:**

| Dado                 | Uso               |
| -------------------- | ----------------- |
| FX daily             | USD/BRL           |
| equities             | ETFs/ações        |
| technical indicators | features técnicas |

---

## 22. Twelve Data

**Uso:** FX, índices, ações, commodities.

**Tipo:** API freemium/paga.

**Pode fornecer:**

| Dado             | Uso              |
| ---------------- | ---------------- |
| USD/BRL intraday | curto prazo      |
| índices globais  | risk-on/risk-off |
| commodities      | termos de troca  |

---

## 23. Polygon.io, Tiingo, Finnhub, Marketstack

**Uso:** dados financeiros globais via API mais estável que scraping.

**Tipo:** pago/freemium.

**Pode fornecer:**

| Dado        | Uso                       |
| ----------- | ------------------------- |
| FX intraday | modelo 5 dias             |
| índices     | risk-on/risk-off          |
| notícias    | sentimento                |
| ações/ETFs  | proxies Brasil/emergentes |

---

## 24. Bloomberg / Refinitiv / FactSet / S&P Capital IQ

**Uso:** produção institucional.

**Tipo:** comercial.

**Vantagem:** qualidade, histórico, licenciamento claro, CDS, curvas, futuros, surveys, calendário, notícias.

**Desvantagem:** custo alto.

---

# 7. Lista consolidada por variável

| Variável                | Fonte recomendada                                | Acesso            | Prioridade    |
| ----------------------- | ------------------------------------------------ | ----------------- | ------------- |
| USD/BRL oficial         | BCB PTAX                                         | API OData         | Essencial     |
| USD/BRL mercado         | Yahoo/yfinance, Alpha Vantage, Twelve Data       | API/lib           | Essencial     |
| Selic/CDI               | BCB SGS                                          | API JSON          | Essencial     |
| Focus câmbio/Selic/IPCA | BCB Expectativas                                 | API OData         | Essencial     |
| Treasury 2Y/10Y         | FRED                                             | API               | Essencial     |
| Fed Funds/SOFR          | FRED                                             | API               | Essencial     |
| VIX                     | FRED/CBOE/Yahoo                                  | API/CSV           | Essencial     |
| DXY                     | Yahoo/FRED/provedor pago                         | API/lib           | Essencial     |
| S&P 500/Nasdaq          | Yahoo/FRED                                       | API/lib           | Essencial     |
| Ibovespa                | Yahoo/B3                                         | API/download      | Essencial     |
| DI futuro               | B3                                               | download/API      | Alta          |
| Dólar futuro            | B3                                               | download/API      | Alta          |
| Curva juros BR          | ANBIMA/B3                                        | API/download      | Alta          |
| IPCA                    | IBGE SIDRA/BCB SGS                               | API               | Alta          |
| Produção industrial     | IBGE SIDRA                                       | API               | Média         |
| Varejo                  | IBGE SIDRA                                       | API               | Média         |
| PIB                     | IBGE SIDRA/Ipeadata                              | API               | Média         |
| Fiscal                  | Tesouro Nacional                                 | API/dados abertos | Alta para 90d |
| Comércio exterior       | Comex Stat/MDIC                                  | CSV/API indireta  | Alta para 90d |
| Petróleo Brent/WTI      | EIA/Yahoo/World Bank                             | API/lib           | Alta          |
| Minério/soja/café       | World Bank/Nasdaq Data Link                      | planilha/API      | Alta          |
| CDS/EMBI                | Bloomberg/Refinitiv/JP Morgan/proxies            | pago/proxy        | Alta          |
| Notícias                | GDELT/NewsAPI/Event Registry                     | API               | Média         |
| Calendário econômico    | Trading Economics/Investing/calendários oficiais | API/scraping      | Média         |
| FedWatch                | CME                                              | site/API paga     | Média/Alta    |

---

# 8. Stack recomendada para automatizar

Para um pipeline simples:

```text
Python
requests
pandas
yfinance
python-bcb
sidrapy
sqlalchemy
duckdb ou PostgreSQL
prefect ou dagster
great_expectations ou pandera
mlflow
```

Para armazenamento:

```text
/raw
  /bcb_ptax
  /bcb_sgs
  /focus
  /fred
  /yahoo
  /ibge_sidra
  /comex
  /b3
  /anbima

/processed
  /daily_features
  /monthly_features
  /targets

/models
  /usdbrl_5d
  /usdbrl_30d
  /usdbrl_90d
```

---

# 9. Arquitetura mínima de atualização

```text
[APIs / CSVs / Scrapers]
        ↓
[Raw Layer: salvar resposta original]
        ↓
[Staging: padronizar data, moeda, timezone, frequência]
        ↓
[Feature Layer: retornos, lags, médias, spreads, volatilidade]
        ↓
[Target Layer: retorno futuro 5d, 30d, 90d]
        ↓
[Model Training / Scoring]
        ↓
[Dashboard / API / Alertas]
```

---

# 10. Meu recorte recomendado para começar

Para um **MVP bom e viável**, eu começaria com estas fontes:

| Bloco              | Fonte                           |
| ------------------ | ------------------------------- |
| Câmbio             | BCB PTAX + Yahoo `USDBRL=X`     |
| Juros Brasil       | BCB SGS + ANBIMA                |
| Expectativas       | BCB Focus                       |
| Juros EUA          | FRED                            |
| Risco global       | FRED/Yahoo VIX                  |
| Dólar global       | Yahoo DXY                       |
| Bolsa local/global | Yahoo Ibovespa, S&P 500, Nasdaq |
| Commodities        | Yahoo + World Bank/EIA          |
| Macro Brasil       | IBGE SIDRA + Ipeadata           |
| Fiscal             | Tesouro Nacional                |
| Setor externo      | Comex Stat                      |

Com isso você já consegue montar um dataset bastante razoável para os três horizontes:

```text
5 dias  → mercado, momentum, volatilidade, VIX, DXY, juros curtos
30 dias → mercado + Focus + juros + commodities + calendário
90 dias → fundamentos macro + fiscal + setor externo + commodities + expectativas
```

O principal cuidado é manter uma regra rígida de **data de disponibilidade**: uma variável só pode entrar no dataset a partir do dia em que ela realmente estava disponível para o mercado. Isso evita que o modelo pareça bom no backtest, mas falhe na prática.

[1]: https://dadosabertos.bcb.gov.br/dataset/taxas-de-cambio-todos-os-boletins-diarios/resource/a97a50fe-e12a-4cf4-b7e9-6575a2e2ece0?utm_source=chatgpt.com "API - Endpoint OData - Banco Central do Brasil"
[2]: https://dadosabertos.bcb.gov.br/dataset/20542-saldo-da-carteira-de-credito-com-recursos-livres---total/resource/6e2b0c97-afab-4790-b8aa-b9542923cf88?utm_source=chatgpt.com "json_serie-sgs-20542 - Banco Central do Brasil"
[3]: https://wilsonfreitas.github.io/python-bcb/sgs.html?utm_source=chatgpt.com "SGS - documentação python-bcb - GitHub Pages"
[4]: https://www.bcb.gov.br/publicacoes/focus?utm_source=chatgpt.com "Focus - Relatório de Mercado - Banco Central do Brasil"
[5]: https://dadosabertos.bcb.gov.br/dataset/expectativas-mercado/resource/029c43d9-70c7-46b4-bea9-42c0696df112?utm_source=chatgpt.com "Expectativas de Mercado - API - Documentação Swagger - Portal de Dados ..."
[6]: https://fred.stlouisfed.org/?utm_source=chatgpt.com "Federal Reserve Economic Data | FRED | St. Louis Fed"
[7]: https://fred.stlouisfed.org/series/VIXCLS/?utm_source=chatgpt.com "CBOE Volatility Index: VIX (VIXCLS) | FRED | St. Louis Fed"
[8]: https://github.com/ranaroussi/yfinance?utm_source=chatgpt.com "Download market data from Yahoo! Finance's API - GitHub"
[9]: https://apisidra.ibge.gov.br/?utm_source=chatgpt.com "Home Page da API Sidra"
[10]: https://ipeadata.gov.br/api/?utm_source=chatgpt.com "Serviço de consulta aos dados do Ipeadata"
[11]: https://www.gov.br/tesouronacional/pt-br/central-de-conteudo/apis?utm_source=chatgpt.com "API's - Tesouro Nacional"
[12]: https://comexstat.mdic.gov.br/pt/home?utm_source=chatgpt.com "Comex Stat - Ministério do Desenvolvimento, Indústria, Comércio e ..."
[13]: https://www.gov.br/mdic/pt-br/assuntos/comercio-exterior/estatisticas/base-de-dados-bruta?utm_source=chatgpt.com "Estatísticas de Comércio Exterior em Dados Abertos"
[14]: https://b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/market-data/historico/?utm_source=chatgpt.com "Histórico | B3"
[15]: https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/b3-for-developers/?utm_source=chatgpt.com "B3 for Developers"
[16]: https://developers.anbima.com.br/pt/documentacao/precos-indices/apis-de-precos/titulos-publicos/?utm_source=chatgpt.com "Títulos Públicos – ANBIMA Developers"
[17]: https://www.cboe.com/en/tradable-products/vix/vix-historical-data/?utm_source=chatgpt.com "Historical Data for Cboe VIX® Index and Other Volatility Indices"
[18]: https://www.eia.gov/opendata/?utm_source=chatgpt.com "Opendata - U.S. Energy Information Administration (EIA)"
[19]: https://thedocs.worldbank.org/en/doc/18675f1d1639c7a34d463f59263ba0a2-0050012025/?utm_source=chatgpt.com "World Bank Commodities Price Data (The Pink Sheet)"
[20]: https://data.nasdaq.com/tools/api?utm_source=chatgpt.com "Nasdaq Data Link APIs: Get financial data via API"
[21]: https://www.cmegroup.com/markets/interest-rates/cme-fedwatch-tool.html?utm_source=chatgpt.com "FedWatch - CME Group"
[22]: https://www.cmegroup.com/market-data/market-data-api/fedwatch-api.html?utm_source=chatgpt.com "FedWatch API - CME Group"
