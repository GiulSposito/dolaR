# Phase 2b — Coleta de Dados Macro Brasil
# Owner: Ada
# Sources: BCB SGS (Selic, IPCA, CDI, reservas, fluxo cambial)
#          BCB Expectativas Focus (câmbio, Selic, IPCA esperados)
#          IBGE SIDRA (IPCA realizado, PMC, PIM)
# Output:  data/raw/bcb_sgs/, data/raw/bcb_focus/, data/raw/ibge/

library(tidyverse)
library(lubridate)
library(here)

DATA_INI <- "2010-01-01"
DATA_FIM  <- as.character(Sys.Date())

# ── 1. BCB SGS — Séries históricas ───────────────────────────────────────────
# Documentação: https://dadosabertos.bcb.gov.br
# Pacote rbcb: rbcb::get_series()

BCB_SERIES <- tribble(
  ~codigo, ~nome,              ~descricao,
  432,     "selic_meta",       "Meta Selic (% a.a.)",
  11,      "selic_diaria",     "Taxa Selic diária acumulada",
  12,      "cdi_diario",       "CDI diário",
  433,     "ipca_mensal",      "IPCA variação mensal (%)",
  13522,   "ipca_acum12m",     "IPCA acumulado 12 meses (%)",
  13621,   "reservas_intl",    "Reservas internacionais — liquidez (US$ bi, mensal)",
  23636,   "saldo_cambial",    "Saldo de câmbio no mercado (US$ mi)",
  24363,   "fluxo_cambial",    "Fluxo cambial financeiro líquido (US$ mi)"
)

collect_bcb_sgs <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(rbcb)

  series_list <- setNames(BCB_SERIES$codigo, BCB_SERIES$nome)

  # A API BCB SGS rejeita períodos muito longos (406).
  # Estratégia: coletar em janelas de 2 anos e concatenar.
  anos_ini <- as.integer(format(as.Date(data_ini), "%Y"))
  anos_fim <- as.integer(format(as.Date(data_fim), "%Y"))
  janelas  <- seq(anos_ini, anos_fim, by = 2)

  sgs_chunks <- map(janelas, function(ano) {
    ini_j <- as.Date(sprintf("%d-01-01", ano))
    fim_j <- min(as.Date(sprintf("%d-12-31", ano + 1)), as.Date(data_fim))
    cat(sprintf("  SGS: coletando %s a %s...\n", ini_j, fim_j))

    tryCatch(
      rbcb::get_series(series_list, start_date = ini_j, end_date = fim_j),
      error = function(e) {
        cat(sprintf("  Aviso SGS janela %s: %s\n", ano, e$message))
        NULL
      }
    )
  })

  # Consolidar: cada elemento da lista é uma lista de tibbles por série
  sgs_long <- map_dfr(compact(sgs_chunks), function(chunk) {
    map2_dfr(chunk, names(chunk), function(df, nome) {
      df |> mutate(serie = nome, date = as.Date(date)) |>
        rename(valor = 2) |> select(date, serie, valor)
    })
  }) |>
    distinct(date, serie, .keep_all = TRUE) |>
    arrange(serie, date)

  write_csv(sgs_long, here("data", "raw", "bcb_sgs", "bcb_sgs_series.csv"))
  cat(sprintf("BCB SGS: %d observações em %d séries\n",
              nrow(sgs_long), n_distinct(sgs_long$serie)))
  invisible(sgs_long)
}

# ── 2. BCB Expectativas Focus ────────────────────────────────────────────────
# Documentação: https://olinda.bcb.gov.br/olinda/servico/Expectativas/versao/v1/swagger-ui3
# Pacote rbcb: rbcb::get_market_expectations()

collect_focus <- function(data_ini = DATA_INI, data_fim = DATA_FIM) {
  library(rbcb)

  # Expectativas anuais (indicadores mais usados no modelo)
  indicadores <- c("Câmbio", "Selic", "IPCA", "PIB Total")

  focus_list <- map(indicadores, function(ind) {
    tryCatch({
      rbcb::get_market_expectations(
        type       = "annual",
        indic      = ind,
        start_date = data_ini,
        end_date   = data_fim
      ) |>
        mutate(indicador = ind)
    }, error = function(e) {
      cat(sprintf("  Aviso: falha ao coletar Focus '%s': %s\n", ind, e$message))
      NULL
    })
  })

  # A API retorna coluna "Data" (maiúsculo) — renomear para "date"
  focus_df <- bind_rows(compact(focus_list)) |>
    rename(date = Data) |>
    arrange(indicador, date)

  write_csv(focus_df, here("data", "raw", "bcb_focus", "focus_expectations.csv"))
  cat(sprintf("Focus: %d observações para %d indicadores\n",
              nrow(focus_df), n_distinct(focus_df$indicador)))
  invisible(focus_df)
}

# ── 3. IBGE SIDRA — IPCA realizado ───────────────────────────────────────────
# Pacote sidrar: https://cran.r-project.org/package=sidrar
# install.packages("sidrar")

collect_ibge <- function() {
  library(sidrar)

  # Tabela 1737: IPCA mensal por grupos
  ipca_raw <- tryCatch(
    sidrar::get_sidra(
      api = "/t/1737/n1/all/v/63,69,2263,2264,2265/p/all/d/v63%202,v69%202,v2263%202,v2264%202,v2265%202"
    ),
    error = function(e) {
      cat("  Aviso IBGE SIDRA:", e$message, "\n")
      NULL
    }
  )

  if (!is.null(ipca_raw)) {
    ipca_clean <- ipca_raw |>
      janitor::clean_names() |>
      mutate(date = lubridate::ym(mes_codigo)) |>
      select(date, variavel, valor)

    write_csv(ipca_clean, here("data", "raw", "ibge", "ipca_sidra.csv"))
    cat(sprintf("IBGE SIDRA IPCA: %d observações\n", nrow(ipca_clean)))
    invisible(ipca_clean)
  }
}

# ── Execução ─────────────────────────────────────────────────────────────────
if (interactive()) {
  cat("Coletando BCB SGS...\n")
  sgs  <- collect_bcb_sgs()

  cat("\nColetando BCB Focus...\n")
  focus <- collect_focus()

  cat("\nColetando IBGE SIDRA...\n")
  ibge <- collect_ibge()

  writeLines(as.character(Sys.time()),
             here("checkpoints", "02b-macro-br.complete"))
  cat("\nFase 2b concluída.\n")
}
