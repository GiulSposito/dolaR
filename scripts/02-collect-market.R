# Phase 2a — Coleta de Dados de Mercado
# Owner: Ada
# Sources: BCB PTAX (USD/BRL oficial), Yahoo Finance (mercado global)
# Output:  data/raw/bcb_ptax/, data/raw/yahoo/

library(tidyverse)
library(lubridate)
library(here)

# Intervalo de coleta
DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── 1. BCB PTAX — USD/BRL oficial ────────────────────────────────────────────
# Pacote rbcb: https://github.com/wilsonfreitas/rbcb
# install.packages("rbcb")

collect_ptax <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(rbcb)

  ptax <- rbcb::get_currency("USD", start_date = data_ini, end_date = data_fim)

  ptax_clean <- ptax |>
    rename(date = date, bid = bid, ask = ask) |>
    mutate(date = as.Date(date)) |>
    arrange(date)

  write_csv(ptax_clean, here("data", "raw", "bcb_ptax", "usd_brl_ptax.csv"))
  cat(sprintf("PTAX: %d observações de %s a %s\n",
              nrow(ptax_clean), min(ptax_clean$date), max(ptax_clean$date)))
  invisible(ptax_clean)
}

# ── 2. Yahoo Finance — Séries de mercado global ───────────────────────────────
# Pacote tidyquant: https://business-science.github.io/tidyquant/
# install.packages("tidyquant")

# Mapa de tickers relevantes para o modelo
YAHOO_TICKERS <- tribble(
  ~ticker,      ~nome,           ~grupo,
  "USDBRL=X",   "usd_brl",       "cambio",
  "DX-Y.NYB",   "dxy",           "cambio",
  "^VIX",       "vix",           "risco",
  "^GSPC",      "sp500",         "bolsa",
  "^IXIC",      "nasdaq",        "bolsa",
  "^BVSP",      "ibovespa",      "bolsa",
  "EWZ",        "ewz",           "brasil",      # ETF Brasil — proxy CDS/risco
  "CL=F",       "petroleo_wti",  "commodities",
  "BZ=F",       "petroleo_brent","commodities",
  "GC=F",       "ouro",          "commodities",
  "HG=F",       "cobre",         "commodities"
)

collect_yahoo <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(tidyquant)

  prices <- tq_get(
    YAHOO_TICKERS$ticker,
    get  = "stock.prices",
    from = data_ini,
    to   = data_fim
  )

  prices_clean <- prices |>
    left_join(YAHOO_TICKERS, by = c("symbol" = "ticker")) |>
    select(date, symbol, nome, grupo, adjusted) |>
    rename(close = adjusted) |>
    arrange(symbol, date)

  write_csv(prices_clean, here("data", "raw", "yahoo", "market_prices.csv"))

  prices_clean |>
    group_by(symbol) |>
    summarise(n = n(), ini = min(date), fim = max(date)) |>
    print()

  invisible(prices_clean)
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando PTAX...\n")
  ptax <- collect_ptax()

  cat("\nColetando Yahoo Finance...\n")
  yahoo <- collect_yahoo()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "02a-market.complete"))
  cat("\nFase 2a concluída.\n")
}
