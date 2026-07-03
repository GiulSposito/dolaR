# Phase 2d — Coleta de Dados B3 (futuros de dólar e DI)
# Owner: Ada
# Sources: B3 via arquivos históricos ou proxy tidyquant
# Output:  data/raw/b3/
# Nota: acesso direto à API B3 requer cadastro; esta fase usa proxies acessíveis.

library(tidyverse)
library(lubridate)
library(here)

DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── Proxies B3 via Yahoo Finance ──────────────────────────────────────────────
# Dólar futuro e DI futuro não têm tickers Yahoo livres.
# Usamos ETFs e índices como proxies para MVP:
#   - BRL=X: câmbio spot (complementar ao PTAX)
#   - Curva DI: será inferida pelo diferencial SGS/FRED

B3_PROXY_TICKERS <- tribble(
  ~ticker,    ~nome,            ~tipo,
  "DOL=F",    "dolar_futuro",   "futuro",   # Dólar futuro (quando disponível)
  "^BVSP",    "ibovespa",       "indice"
)

collect_b3_proxies <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(tidyquant)

  proxies <- tq_get(
    B3_PROXY_TICKERS$ticker,
    get  = "stock.prices",
    from = data_ini,
    to   = data_fim
  ) |>
    left_join(B3_PROXY_TICKERS, by = c("symbol" = "ticker")) |>
    select(date, symbol, nome, tipo, adjusted) |>
    rename(close = adjusted) |>
    arrange(nome, date)

  write_csv(proxies, here("data", "raw", "b3", "b3_proxies.csv"))
  cat(sprintf("B3 proxies: %d observações\n", nrow(proxies)))
  invisible(proxies)
}

# ── Nota sobre dados completos B3 ─────────────────────────────────────────────
# Para acesso completo a futuros DI e dólar futuro com ajuste diário:
# 1. Cadastro em B3 for Developers: https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/b3-for-developers/
# 2. Download histórico manual em: https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/market-data/historico/
# 3. Pacotes comunitários: cotahist (CRAN)
#
# Arquivos B3 históricos (formato BVBG): colocar em data/raw/b3/ e parsear
# com cotahist::read_market_data()

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando proxies B3...\n")
  b3 <- collect_b3_proxies()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "02d-b3.complete"))
  cat("\nFase 2d concluída.\n")
  cat("Para dados completos de futuros B3, ver comentários no script.\n")
}
