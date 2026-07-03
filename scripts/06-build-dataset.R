# Phase 3 — Construção do Dataset Unificado
# Owner: Ada
# Input:  data/raw/ (todas as fontes)
# Output: data/processed/daily_dataset.rds  — dataset diário completo
#         data/processed/model_dataset.rds  — dataset com targets, sem leakage
#
# REGRA CRÍTICA: cada variável só entra no dataset a partir do dia em que
# estava disponível para o mercado (evitar leakage temporal).

library(tidyverse)
library(lubridate)
library(timetk)
library(here)

# ── 1. Carregar dados coletados ───────────────────────────────────────────────

load_raw_data <- function() {
  raw <- list()

  # USD/BRL PTAX
  ptax_path <- here("data", "raw", "bcb_ptax", "usd_brl_ptax.csv")
  if (file.exists(ptax_path)) {
    raw$ptax <- read_csv(ptax_path, show_col_types = FALSE) |>
      select(date, ask) |>
      rename(usd_brl_ptax = ask)
  }

  # Yahoo Finance (mercado global)
  yahoo_path <- here("data", "raw", "yahoo", "market_prices.csv")
  if (file.exists(yahoo_path)) {
    raw$yahoo <- read_csv(yahoo_path, show_col_types = FALSE) |>
      select(date, nome, close) |>
      pivot_wider(names_from = nome, values_from = close)
  }

  # BCB SGS
  sgs_path <- here("data", "raw", "bcb_sgs", "bcb_sgs_series.csv")
  if (file.exists(sgs_path)) {
    raw$sgs <- read_csv(sgs_path, show_col_types = FALSE) |>
      select(date, serie, valor) |>
      pivot_wider(names_from = serie, values_from = valor)
  }

  # FRED (dados EUA — alguns são mensais, interpolados para diário)
  fred_path <- here("data", "raw", "fred", "fred_series.csv")
  if (file.exists(fred_path)) {
    raw$fred <- read_csv(fred_path, show_col_types = FALSE) |>
      select(date, nome, value) |>
      pivot_wider(names_from = nome, values_from = value)
  }

  # BCB Focus (semanal — será preenchido para frente até próxima divulgação)
  focus_path <- here("data", "raw", "bcb_focus", "focus_expectations.csv")
  if (file.exists(focus_path)) {
    raw$focus <- read_csv(focus_path, show_col_types = FALSE)
  }

  # IBGE SIDRA (mensal)
  ibge_path <- here("data", "raw", "ibge", "ipca_sidra.csv")
  if (file.exists(ibge_path)) {
    raw$ibge <- read_csv(ibge_path, show_col_types = FALSE) |>
      filter(date >= as.Date("2010-01-01")) |>
      pivot_wider(names_from = variavel, values_from = valor) |>
      janitor::clean_names()
  }

  # BCB SGS fiscal/atividade (script 07)
  sgs_fiscal_path <- here("data", "raw", "bcb_sgs_fiscal", "bcb_sgs_fiscal.csv")
  if (file.exists(sgs_fiscal_path)) {
    raw$sgs_fiscal <- read_csv(sgs_fiscal_path, show_col_types = FALSE) |>
      select(date, serie, valor) |>
      pivot_wider(names_from = serie, values_from = valor)
  }

  # IBGE SIDRA atividade — PIM, PIB, PNAD (script 07)
  activity_path <- here("data", "raw", "ibge", "activity_sidra.csv")
  if (file.exists(activity_path)) {
    raw$activity_sidra <- read_csv(activity_path, show_col_types = FALSE) |>
      select(date, serie, valor) |>
      pivot_wider(names_from = serie, values_from = valor)
  }

  # FRED adicional — commodities, breakevens, spread (script 08)
  fred_add_path <- here("data", "raw", "fred", "fred_additional.csv")
  if (file.exists(fred_add_path)) {
    raw$fred_add <- read_csv(fred_add_path, show_col_types = FALSE) |>
      select(date, nome, value) |>
      pivot_wider(names_from = nome, values_from = value)
  }

  raw
}

# ── 2. Grid de datas — apenas dias úteis com PTAX disponível ─────────────────

build_date_grid <- function(raw) {
  if (is.null(raw$ptax)) stop("PTAX não carregado — rodar 02-collect-market.R")

  raw$ptax |>
    filter(!is.na(usd_brl_ptax)) |>
    select(date) |>
    arrange(date)
}

# ── 3. Join de todas as fontes no grid de datas ───────────────────────────────
# Estratégia:
#   - Dados diários (PTAX, Yahoo): join direto
#   - Dados mensais (IPCA, PIB): forward-fill — só disponível após divulgação
#   - Dados semanais (Focus): forward-fill — só disponível após divulgação

build_daily_dataset <- function(raw, date_grid) {
  ds <- date_grid

  # Dados diários
  if (!is.null(raw$ptax))  ds <- left_join(ds, raw$ptax,  by = "date")
  if (!is.null(raw$yahoo)) ds <- left_join(ds, raw$yahoo, by = "date")
  if (!is.null(raw$fred))  ds <- left_join(ds, raw$fred,  by = "date")
  if (!is.null(raw$sgs)) {
    # Identificar séries diárias vs mensais disponíveis
    sgs_cols <- names(raw$sgs)
    cols_diario  <- intersect(sgs_cols, c("selic_meta", "selic_diaria", "cdi_diario",
                                          "reservas_intl", "saldo_cambial", "fluxo_cambial"))
    cols_mensal  <- intersect(sgs_cols, c("ipca_mensal", "ipca_acum12m"))

    # Join direto para séries diárias
    if (length(cols_diario) > 0) {
      sgs_diario <- raw$sgs |> select(date, all_of(cols_diario))
      ds <- left_join(ds, sgs_diario, by = "date")
    }

    # Forward-fill para séries mensais (evitar leakage)
    if (length(cols_mensal) > 0) {
      sgs_mensal <- raw$sgs |> select(date, all_of(cols_mensal)) |>
        filter(if_any(all_of(cols_mensal), ~ !is.na(.)))
      ds <- ds |>
        left_join(sgs_mensal, by = "date") |>
        arrange(date) |>
        fill(all_of(cols_mensal), .direction = "down")
    }
  }

  # BCB Focus (semanal → forward-fill até próxima divulgação)
  if (!is.null(raw$focus)) {
    focus_wide <- raw$focus |>
      select(date, indicador, Mediana) |>
      distinct(date, indicador, .keep_all = TRUE) |>
      pivot_wider(names_from = indicador, values_from = Mediana,
                  names_prefix = "focus_") |>
      janitor::clean_names() |>
      arrange(date)
    ds <- ds |>
      left_join(focus_wide, by = "date") |>
      arrange(date) |>
      fill(starts_with("focus_"), .direction = "down")
  }

  # IBGE SIDRA (mensal → forward-fill)
  if (!is.null(raw$ibge)) {
    ds <- ds |>
      left_join(raw$ibge, by = "date") |>
      arrange(date) |>
      fill(starts_with("ipca_"), .direction = "down")
  }

  # BCB SGS fiscal/atividade (todas mensais → forward-fill)
  if (!is.null(raw$sgs_fiscal)) {
    sgs_f_cols <- setdiff(names(raw$sgs_fiscal), "date")
    ds <- ds |>
      left_join(raw$sgs_fiscal, by = "date") |>
      arrange(date) |>
      fill(all_of(sgs_f_cols), .direction = "down")
  }

  # IBGE SIDRA atividade (mensal/trimestral → forward-fill)
  if (!is.null(raw$activity_sidra)) {
    act_cols <- setdiff(names(raw$activity_sidra), "date")
    ds <- ds |>
      left_join(raw$activity_sidra, by = "date") |>
      arrange(date) |>
      fill(all_of(act_cols), .direction = "down")
  }

  # FRED adicional — diários (breakevens, HY spread): join direto
  #                — mensais (commodities, sentiment): forward-fill
  if (!is.null(raw$fred_add)) {
    cols_diario_add <- intersect(names(raw$fred_add),
                                 c("breakeven_10y", "breakeven_5y", "us_hy_spread"))
    cols_mensal_add <- intersect(names(raw$fred_add),
                                 c("minerio_ferro", "soja", "consumer_sentiment_us"))

    if (length(cols_diario_add) > 0) {
      ds <- left_join(ds, select(raw$fred_add, date, all_of(cols_diario_add)), by = "date")
    }
    if (length(cols_mensal_add) > 0) {
      fred_m <- raw$fred_add |>
        select(date, all_of(cols_mensal_add)) |>
        filter(if_any(all_of(cols_mensal_add), ~ !is.na(.)))
      ds <- ds |>
        left_join(fred_m, by = "date") |>
        arrange(date) |>
        fill(all_of(cols_mensal_add), .direction = "down")
    }
  }

  ds |> arrange(date)
}

# ── 4. Criar variáveis-alvo (targets) ─────────────────────────────────────────
# IMPORTANTE: target calcula preço FUTURO usando usd_brl_ptax
# Só será conhecido nos dias t+5, t+30, t+90 (não há leakage no treino)

create_targets <- function(ds) {
  price <- ds$usd_brl_ptax

  ds |>
    mutate(
      # Retorno logarítmico — mais estável que retorno simples
      target_5d  = log(lead(usd_brl_ptax, 5)  / usd_brl_ptax),
      target_30d = log(lead(usd_brl_ptax, 30) / usd_brl_ptax),
      target_90d = log(lead(usd_brl_ptax, 90) / usd_brl_ptax),

      # Direção (para métricas de classificação)
      dir_5d  = case_when(target_5d  > 0 ~ "alta", target_5d  < 0 ~ "queda", TRUE ~ "estavel"),
      dir_30d = case_when(target_30d > 0 ~ "alta", target_30d < 0 ~ "queda", TRUE ~ "estavel"),
      dir_90d = case_when(target_90d > 0 ~ "alta", target_90d < 0 ~ "queda", TRUE ~ "estavel")
    )
}

# ── 5. Salvar dataset ─────────────────────────────────────────────────────────

save_datasets <- function(ds_with_targets) {
  # Dataset completo (inclui targets futuros — usar apenas para EDA)
  write_rds(ds_with_targets,
            here("data", "processed", "daily_dataset.rds"))

  # Dataset para modelagem: remove linhas sem target (últimas 90 observações)
  model_ds <- ds_with_targets |>
    filter(!is.na(target_5d), !is.na(target_30d), !is.na(target_90d))

  write_rds(model_ds, here("data", "processed", "model_dataset.rds"))

  cat(sprintf("Dataset diário: %d observações, %d variáveis\n",
              nrow(ds_with_targets), ncol(ds_with_targets)))
  cat(sprintf("Dataset para modelagem: %d observações\n", nrow(model_ds)))
  cat(sprintf("Período: %s a %s\n",
              min(model_ds$date), max(model_ds$date)))
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Carregando dados brutos...\n")
  raw <- load_raw_data()

  cat("Construindo grid de datas...\n")
  date_grid <- build_date_grid(raw)

  cat("Juntando fontes...\n")
  ds <- build_daily_dataset(raw, date_grid)

  cat("Criando targets...\n")
  ds_with_targets <- create_targets(ds)

  cat("Salvando datasets...\n")
  save_datasets(ds_with_targets)

  writeLines(as.character(Sys.time()),
             here("checkpoints", "03-build-dataset.complete"))
  cat("\nFase 3 concluída. Próximo: scripts/07-eda.R\n")
}
