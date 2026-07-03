# Phase 2f — Coleta: Indicadores Globais Adicionais (FRED)
# Owner: Ada
# Sources: FRED — commodities, inflação implícita EUA, spread crédito global
# Requires: FRED_API_KEY em .Renviron.local
# Output:   data/raw/fred/fred_additional.csv

library(tidyverse)
library(lubridate)
library(here)

DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── Séries FRED adicionais ────────────────────────────────────────────────────
FRED_ADD <- tribble(
  ~series_id,        ~nome,                   ~descricao,                         ~grupo,          ~freq,
  # Commodities (mensais — World Bank via FRED)
  "PIORECRUSDM",     "minerio_ferro",          "Minério de ferro (US$/ton, mensal)", "commodities",   "m",
  "PSOYBUSDM",       "soja",                   "Soja preço (US$/ton, mensal)",       "commodities",   "m",
  # Inflação implícita EUA (breakevens diários)
  "T10YIE",          "breakeven_10y",           "Inflação implícita 10 anos EUA",    "inflacao_us",   "d",
  "T5YIE",           "breakeven_5y",            "Inflação implícita 5 anos EUA",     "inflacao_us",   "d",
  # Spread crédito / risco global
  "BAMLH0A0HYM2",    "us_hy_spread",            "Spread High Yield EUA (bps)",       "risco_global",  "d",
  # Confiança consumidor EUA (mensal)
  "UMCSENT",         "consumer_sentiment_us",   "Confiança consumidor Michigan EUA", "atividade_us",  "m"
)

# ── Coleta via fredr ──────────────────────────────────────────────────────────
collect_fred_additional <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(fredr)

  api_key <- Sys.getenv("FRED_API_KEY")
  if (nchar(api_key) == 0) {
    stop("FRED_API_KEY não encontrada. Configure em .Renviron.local.")
  }
  fredr_set_key(api_key)

  fred_list <- map2(FRED_ADD$series_id, FRED_ADD$freq, function(sid, freq) {
    tryCatch({
      fredr(
        series_id         = sid,
        observation_start = as.Date(data_ini),
        observation_end   = as.Date(data_fim),
        frequency         = freq
      ) |>
        mutate(series_id = sid)
    }, error = function(e) {
      cat(sprintf("  Aviso FRED '%s': %s\n", sid, e$message))
      NULL
    })
  })

  fred_df <- bind_rows(compact(fred_list)) |>
    left_join(select(FRED_ADD, series_id, nome, descricao, grupo),
              by = "series_id") |>
    select(date, series_id, nome, grupo, value) |>
    arrange(nome, date)

  write_csv(fred_df, here("data", "raw", "fred", "fred_additional.csv"))

  fred_df |>
    group_by(nome) |>
    summarise(n = n(), ini = min(date), fim = max(date)) |>
    print()

  invisible(fred_df)
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando FRED indicadores globais adicionais...\n")
  fred_add <- collect_fred_additional()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "08-global-indicators.complete"))
  cat("\nFase 2f concluída.\n")
}
