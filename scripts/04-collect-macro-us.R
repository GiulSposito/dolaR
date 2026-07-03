# Phase 2c — Coleta de Dados Macro EUA
# Owner: Ada
# Sources: FRED (Federal Reserve Economic Data)
# Requires: FRED_API_KEY em .Renviron.local
# Output:   data/raw/fred/

library(tidyverse)
library(lubridate)
library(here)

DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── Séries FRED relevantes para USD/BRL ──────────────────────────────────────
FRED_SERIES <- tribble(
  ~series_id,   ~nome,            ~descricao,                 ~grupo,        ~freq,
  "DGS2",       "treasury_2y",    "Treasury yield 2 anos",    "juros_us",    "d",
  "DGS10",      "treasury_10y",   "Treasury yield 10 anos",   "juros_us",    "d",
  "FEDFUNDS",   "fed_funds",      "Fed Funds Rate",            "juros_us",    "m",
  "SOFR",       "sofr",           "Secured Overnight Rate",   "juros_us",    "d",
  "VIXCLS",     "vix_fred",       "CBOE VIX (FRED)",          "risco",       "d",
  "CPIAUCSL",   "cpi_us",         "CPI EUA (nível)",          "inflacao_us", "m",
  "CPILFESL",   "core_cpi_us",    "Core CPI EUA",             "inflacao_us", "m",
  "PCEPI",      "pce_us",         "PCE Price Index",          "inflacao_us", "m",
  "UNRATE",     "desemprego_us",  "Taxa desemprego EUA",      "atividade_us","m",
  "DTWEXBGS",   "dxy_fred",       "Dólar amplo (FRED)",       "cambio",      "d"
)

# ── Coleta via fredr ──────────────────────────────────────────────────────────
# Pacote fredr: https://cran.r-project.org/package=fredr
# install.packages("fredr")
# Chave: fredr::fredr_set_key(Sys.getenv("FRED_API_KEY"))

collect_fred <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(fredr)

  api_key <- Sys.getenv("FRED_API_KEY")
  if (nchar(api_key) == 0) {
    stop("FRED_API_KEY não encontrada.\n",
         "Configure em .Renviron.local: FRED_API_KEY=sua_chave_aqui\n",
         "Obter chave gratuita em: https://fred.stlouisfed.org/docs/api/api_key.html")
  }
  fredr_set_key(api_key)

  fred_list <- map2(FRED_SERIES$series_id, FRED_SERIES$freq, function(sid, freq) {
    tryCatch({
      fredr(
        series_id         = sid,
        observation_start = as.Date(data_ini),
        observation_end   = as.Date(data_fim),
        frequency         = freq   # "d" para diárias, "m" para mensais
      ) |>
        mutate(series_id = sid)
    }, error = function(e) {
      cat(sprintf("  Aviso FRED '%s': %s\n", sid, e$message))
      NULL
    })
  })

  fred_df <- bind_rows(compact(fred_list)) |>
    left_join(select(FRED_SERIES, series_id, nome, descricao, grupo),
              by = "series_id") |>
    select(date, series_id, nome, grupo, value) |>
    arrange(nome, date)

  write_csv(fred_df, here("data", "raw", "fred", "fred_series.csv"))

  fred_df |>
    group_by(nome) |>
    summarise(n = n(), ini = min(date), fim = max(date)) |>
    print()

  invisible(fred_df)
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando FRED...\n")
  fred <- collect_fred()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "02c-macro-us.complete"))
  cat("\nFase 2c concluída.\n")
}
