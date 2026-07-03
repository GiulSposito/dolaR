# Phase 2e — Coleta: Atividade Econômica BR + Fiscal
# Owner: Ada
# Sources: BCB SGS (fiscal, IBC-Br, balança, dívida, desemprego)
#          IBGE SIDRA (PIM, PIB trimestral, PNAD desemprego)
# Output:  data/raw/bcb_sgs_fiscal/bcb_sgs_fiscal.csv
#          data/raw/ibge/activity_sidra.csv

library(tidyverse)
library(lubridate)
library(here)

DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── 1. BCB SGS — Fiscal e Atividade ──────────────────────────────────────────
# Séries mensais — forward-fill no build dataset

SGS_FISCAL <- tribble(
  ~codigo, ~nome,               ~descricao,
  5364,    "resultado_primario", "Resultado primário gov. central (R$ mi)",
  11426,   "resultado_nominal",  "Resultado nominal gov. central (R$ mi)",
  13762,   "dbgg_pib",           "Dívida bruta gov. geral % PIB",
  22708,   "balanca_comercial_bcb", "Balança comercial saldo acumulado (US$ mi)",
  4380,    "ibc_br",             "IBC-Br — proxy PIB mensal (índice)",
  24369,   "desemprego_br"  ,    "Taxa desemprego PNAD mensal (%)"
)

collect_sgs_fiscal <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(rbcb)

  anos_ini <- as.integer(format(as.Date(data_ini), "%Y"))
  anos_fim <- as.integer(format(as.Date(data_fim), "%Y"))
  janelas  <- seq(anos_ini, anos_fim, by = 2)

  series_list <- setNames(SGS_FISCAL$codigo, SGS_FISCAL$nome)

  sgs_chunks <- map(janelas, function(ano) {
    ini_j <- as.Date(sprintf("%d-01-01", ano))
    fim_j <- min(as.Date(sprintf("%d-12-31", ano + 1)), as.Date(data_fim))
    cat(sprintf("  SGS fiscal: %s a %s...\n", ini_j, fim_j))
    tryCatch(
      rbcb::get_series(series_list, start_date = ini_j, end_date = fim_j),
      error = function(e) {
        cat(sprintf("  Aviso SGS janela %d: %s\n", ano, e$message))
        NULL
      }
    )
  })

  sgs_long <- map_dfr(compact(sgs_chunks), function(chunk) {
    map2_dfr(chunk, names(chunk), function(df, nome) {
      df |> mutate(serie = nome, date = as.Date(date)) |>
        rename(valor = 2) |> select(date, serie, valor)
    })
  }) |>
    distinct(date, serie, .keep_all = TRUE) |>
    arrange(serie, date)

  write_csv(sgs_long, here("data", "raw", "bcb_sgs_fiscal", "bcb_sgs_fiscal.csv"))
  cat(sprintf("BCB SGS fiscal: %d obs em %d séries\n",
              nrow(sgs_long), n_distinct(sgs_long$serie)))

  sgs_long |>
    group_by(serie) |>
    summarise(n = n(), ini = min(date), fim = max(date)) |>
    print()

  invisible(sgs_long)
}

# ── 2. IBGE SIDRA — PIM, PIB, PNAD ───────────────────────────────────────────

collect_activity_sidra <- function() {
  library(sidrar)
  library(janitor)

  results <- list()

  # PIM-PF: tabela 3653, variável 3135 (índice geral, base 2012=100)
  # Disponível até jan/2022 nesta tabela — complementar futuramente
  cat("  Coletando PIM (tabela 3653)...\n")
  pim <- tryCatch({
    sidrar::get_sidra(
      api = "/t/3653/n1/all/v/3135/p/all/c544/129314/d/v3135%201"
    ) |>
      janitor::clean_names() |>
      mutate(
        date = lubridate::ym(mes_codigo),
        serie = "pim_geral",
        valor = as.numeric(valor)
      ) |>
      select(date, serie, valor) |>
      filter(!is.na(valor), date >= as.Date("2010-01-01"))
  }, error = function(e) {
    cat("  Aviso PIM:", e$message, "\n")
    NULL
  })
  if (!is.null(pim)) {
    cat(sprintf("  PIM: %d obs (%s a %s)\n", nrow(pim), min(pim$date), max(pim$date)))
    results$pim <- pim
  }

  # PIB trimestral via SIDRA 5932 descartado — tabela retorna apenas NAs.
  # IBC-Br (proxy mensal do PIB) já coletado em bcb_sgs_fiscal via SGS 4380.

  # PNAD Contínua: tabela 6381, variável 4099 (taxa desemprego trimestral)
  cat("  Coletando PNAD desemprego (tabela 6381)...\n")
  pnad <- tryCatch({
    sidrar::get_sidra(
      api = "/t/6381/n1/all/v/4099/p/all"
    ) |>
      janitor::clean_names() |>
      mutate(
        # Código YYYYMM — usar o mês do fim do trimestre móvel como data
        date = as.Date(paste0(
          substr(trimestre_movel_codigo, 1, 4), "-",
          substr(trimestre_movel_codigo, 5, 6), "-01"
        )),
        serie = "desemprego_pnad_trimestral",
        valor = as.numeric(valor)
      ) |>
      select(date, serie, valor) |>
      filter(!is.na(valor), date >= as.Date("2012-01-01"))
  }, error = function(e) {
    cat("  Aviso PNAD:", e$message, "\n")
    NULL
  })
  if (!is.null(pnad)) {
    cat(sprintf("  PNAD: %d obs (%s a %s)\n", nrow(pnad), min(pnad$date), max(pnad$date)))
    results$pnad <- pnad
  }

  # Consolidar tudo em formato long
  activity_df <- bind_rows(compact(results)) |>
    distinct(date, serie, .keep_all = TRUE) |>
    arrange(serie, date)

  write_csv(activity_df, here("data", "raw", "ibge", "activity_sidra.csv"))
  cat(sprintf("IBGE atividade: %d obs em %d séries\n",
              nrow(activity_df), n_distinct(activity_df$serie)))

  invisible(activity_df)
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando BCB SGS fiscal/atividade...\n")
  sgs_fiscal <- collect_sgs_fiscal()

  cat("\nColetando IBGE SIDRA atividade...\n")
  activity <- collect_activity_sidra()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "07-fiscal-activity.complete"))
  cat("\nFase 2e concluída.\n")
}
