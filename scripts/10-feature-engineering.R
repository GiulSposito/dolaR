# Fase 5 — Feature Engineering
# Owner: Grace
# Input:  data/processed/model_dataset.rds   — dataset sem leakage de target
# Output: data/processed/features_dataset.rds — dataset com features engenheiradas
#         outputs/tables/fe-feature-summary.csv
#         outputs/tables/fe-correlation-features.csv
#         reports/10-fe-summary.txt
#
# Estratégia: features em 5 grupos alinhados ao briefing
#   G1. Retornos e momentum do USD/BRL
#   G2. Volatilidade realizada
#   G3. Spreads macrofinanceiros (juros, risco, termos de troca)
#   G4. Retornos de variáveis externas (DXY, VIX, EWZ, commodities)
#   G5. Calendário (dia da semana, fim de mês, sazonalidade)
#
# Nota: NÃO cria features com dado futuro. Todas as janelas olham para trás.
# Nota: saldo_cambial descartado (<14 obs). us_hy_spread e pim_geral entram
#       mas serão candidatos à remoção posterior por cobertura limitada.

library(tidyverse)
library(lubridate)
library(here)
library(slider)   # rolling functions (slide_dbl)
library(skimr)

dir.create(here("outputs", "tables"),  recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),            recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),        recursive = TRUE, showWarnings = FALSE)

section <- function(title) message(sprintf("\n══ %s ══", title))

# ── Carregar dados ─────────────────────────────────────────────────────────────

section("Carregando model_dataset")
ds_raw <- readRDS(here("data", "processed", "model_dataset.rds")) |>
  arrange(date)

message(sprintf("  Entrada: %d obs × %d vars  (%s a %s)",
                nrow(ds_raw), ncol(ds_raw), min(ds_raw$date), max(ds_raw$date)))

# Séries mensais/semanais chegam com NAs nos dias sem publicação.
# Aplicar forward-fill nas colunas que precisam disso antes de criar features.
# Inclui: fed_funds, cpi_us, core_cpi_us, fluxo_cambial, e demais mensais
# que não foram preenchidas no build-dataset.
mensais_us <- c("fed_funds", "cpi_us", "core_cpi_us", "pce_us",
                "desemprego_us", "consumer_sentiment_us",
                "minerio_ferro", "soja")
mensais_br <- c("fluxo_cambial", "resultado_primario", "resultado_nominal",
                "dbgg_pib", "balanca_comercial_bcb", "ibc_br",
                "desemprego_br", "pim_geral")
mensais_ff <- intersect(c(mensais_us, mensais_br), names(ds_raw))

ds <- ds_raw |>
  tidyr::fill(all_of(mensais_ff), .direction = "down")

n_filled <- sum(sapply(mensais_ff, function(v)
  sum(!is.na(ds[[v]])) - sum(!is.na(ds_raw[[v]]))))
message(sprintf("  Forward-fill aplicado em %d séries mensais (%d células preenchidas)",
                length(mensais_ff), n_filled))

# ══════════════════════════════════════════════════════════════════════════════
# G1 — Retornos e Momentum do USD/BRL
# ══════════════════════════════════════════════════════════════════════════════

section("G1 — Retornos e Momentum USD/BRL")

ds <- ds |>
  mutate(
    # Retornos logarítmicos passados
    ret_usd_1d   = log(usd_brl_ptax / lag(usd_brl_ptax, 1)),
    ret_usd_5d   = log(usd_brl_ptax / lag(usd_brl_ptax, 5)),
    ret_usd_10d  = log(usd_brl_ptax / lag(usd_brl_ptax, 10)),
    ret_usd_21d  = log(usd_brl_ptax / lag(usd_brl_ptax, 21)),
    ret_usd_63d  = log(usd_brl_ptax / lag(usd_brl_ptax, 63)),

    # Médias móveis (preço)
    ma_usd_5d    = slide_dbl(usd_brl_ptax, mean, .before = 4,  .complete = TRUE),
    ma_usd_21d   = slide_dbl(usd_brl_ptax, mean, .before = 20, .complete = TRUE),
    ma_usd_63d   = slide_dbl(usd_brl_ptax, mean, .before = 62, .complete = TRUE),

    # Distância da média (momentum de posição relativa)
    dist_ma_5d   = usd_brl_ptax / ma_usd_5d  - 1,
    dist_ma_21d  = usd_brl_ptax / ma_usd_21d - 1,
    dist_ma_63d  = usd_brl_ptax / ma_usd_63d - 1,

    # Máximo/mínimo recente (drawdown e extensão)
    max_63d      = slide_dbl(usd_brl_ptax, max, .before = 62, .complete = TRUE),
    min_63d      = slide_dbl(usd_brl_ptax, min, .before = 62, .complete = TRUE),
    drawdown_63d = usd_brl_ptax / max_63d - 1,   # queda desde máxima recente
    range_63d    = (usd_brl_ptax - min_63d) / (max_63d - min_63d)  # posição no range
  )

message("  G1: 14 features criadas")

# ══════════════════════════════════════════════════════════════════════════════
# G2 — Volatilidade Realizada
# ══════════════════════════════════════════════════════════════════════════════

section("G2 — Volatilidade realizada")

ds <- ds |>
  mutate(
    # Volatilidade anualizada do USD/BRL (usando ret_usd_1d já criado)
    vol_usd_5d   = slide_dbl(ret_usd_1d, sd, .before = 4,  .complete = TRUE) * sqrt(252),
    vol_usd_21d  = slide_dbl(ret_usd_1d, sd, .before = 20, .complete = TRUE) * sqrt(252),
    vol_usd_63d  = slide_dbl(ret_usd_1d, sd, .before = 62, .complete = TRUE) * sqrt(252),

    # Razão de volatilidade curta/longa (spike de vol)
    vol_ratio    = vol_usd_5d / vol_usd_21d,

    # Volatilidade realizada do VIX (proxy de aversão a risco global)
    ret_vix_1d   = log(vix / lag(vix, 1)),
    vol_vix_21d  = slide_dbl(ret_vix_1d, sd, .before = 20, .complete = TRUE) * sqrt(252)
  )

message("  G2: 6 features criadas (+ ret_vix_1d auxiliar)")

# ══════════════════════════════════════════════════════════════════════════════
# G3 — Spreads Macrofinanceiros
# ══════════════════════════════════════════════════════════════════════════════

section("G3 — Spreads macrofinanceiros")

ds <- ds |>
  mutate(
    # Diferencial de juros Brasil x EUA (carry trade)
    spread_selic_fed    = selic_meta - fed_funds,
    spread_cdi_sofr     = if_else(!is.na(sofr), cdi_diario * 252 - sofr, NA_real_),

    # Curva de juros EUA (sinal de recessão/política monetária)
    spread_10y_2y_us    = treasury_10y - treasury_2y,

    # Spread inflação (pressão diferencial)
    spread_ipca_cpi     = ipca_acum12m - cpi_us,

    # Breakeven implícito (expectativa de inflação EUA) — já no dataset
    # breakeven_10y e breakeven_5y usados diretamente como features brutas

    # EWZ como proxy de CDS Brasil (risco-país local)
    ret_ewz_5d          = log(ewz / lag(ewz, 5)),
    ret_ewz_21d         = log(ewz / lag(ewz, 21)),

    # Fluxo cambial acumulado (pressão de oferta/demanda)
    fluxo_acum_21d      = slide_dbl(fluxo_cambial, sum, .before = 20, .complete = TRUE),
    fluxo_acum_63d      = slide_dbl(fluxo_cambial, sum, .before = 62, .complete = TRUE)
  )

message("  G3: 10 features criadas")

# ══════════════════════════════════════════════════════════════════════════════
# G4 — Retornos de variáveis externas (DXY, VIX, commodities, renda variável)
# ══════════════════════════════════════════════════════════════════════════════

section("G4 — Retornos externos")

ds <- ds |>
  mutate(
    # DXY — força global do dólar
    ret_dxy_1d    = log(dxy / lag(dxy, 1)),
    ret_dxy_5d    = log(dxy / lag(dxy, 5)),
    ret_dxy_21d   = log(dxy / lag(dxy, 21)),

    # VIX — aversão a risco global
    ret_vix_5d    = log(vix / lag(vix, 5)),
    ret_vix_21d   = log(vix / lag(vix, 21)),

    # Petróleo (termos de troca Brasil)
    ret_oil_5d    = log(petroleo_brent / lag(petroleo_brent, 5)),
    ret_oil_21d   = log(petroleo_brent / lag(petroleo_brent, 21)),

    # Minério de ferro
    ret_ferro_5d  = if_else(!is.na(minerio_ferro),
                            log(minerio_ferro / lag(minerio_ferro, 5)), NA_real_),
    ret_ferro_21d = if_else(!is.na(minerio_ferro),
                            log(minerio_ferro / lag(minerio_ferro, 21)), NA_real_),

    # Ouro (proxy de aversão a risco / dólar fraco)
    ret_ouro_5d   = log(ouro / lag(ouro, 5)),
    ret_ouro_21d  = log(ouro / lag(ouro, 21)),

    # Ibovespa — apetite a risco local
    ret_ibov_5d   = log(ibovespa / lag(ibovespa, 5)),
    ret_ibov_21d  = log(ibovespa / lag(ibovespa, 21)),

    # S&P 500 — apetite a risco global
    ret_sp500_5d  = log(sp500 / lag(sp500, 5)),
    ret_sp500_21d = log(sp500 / lag(sp500, 21)),

    # Erro de expectativa do Focus (câmbio esperado vs realizado)
    # Quanto o mercado antecipa vs onde estamos hoje
    erro_focus    = if_else(!is.na(focus_cambio),
                            log(focus_cambio / usd_brl_ptax), NA_real_)
  )

message("  G4: 16 features criadas")

# ══════════════════════════════════════════════════════════════════════════════
# G5 — Calendário e Sazonalidade
# ══════════════════════════════════════════════════════════════════════════════

section("G5 — Calendário")

ds <- ds |>
  mutate(
    dia_semana      = wday(date, week_start = 1L),          # 1=seg … 5=sex
    mes             = month(date),
    trimestre       = quarter(date),
    fim_de_mes      = if_else(day(date + days(1)) == 1L | month(date + days(1)) != mes,
                              1L, 0L),
    semana_do_ano   = isoweek(date),
    # Proxies de eventos monetários: meses típicos de Copom (bimestral) e FOMC
    # Copom: jan, mar, mai, jun/jul, ago, set, out/nov, dez (reuniões a cada ~45 dias)
    # FOMC: jan/fev, mar, mai, jun, jul, set, nov, dez
    # Usamos dummies simples de mês — modelos não lineares capturarão os efeitos
    mes_copom       = if_else(mes %in% c(1L, 3L, 5L, 7L, 9L, 11L), 1L, 0L),
    mes_fomc        = if_else(mes %in% c(2L, 3L, 5L, 6L, 7L, 9L, 11L, 12L), 1L, 0L)
  )

message("  G5: 8 features criadas")

# ══════════════════════════════════════════════════════════════════════════════
# Limpeza final — remover colunas auxiliares temporárias e saldo_cambial
# ══════════════════════════════════════════════════════════════════════════════

section("Consolidação do dataset de features")

# saldo_cambial: descartada (< 14 obs úteis — Ada recomendou no EDA)
ds <- ds |> select(-any_of("saldo_cambial"))

# Quantas obs completas temos?
n_complete <- sum(complete.cases(
  ds |> select(starts_with("ret_"), starts_with("vol_"), starts_with("spread_"),
               starts_with("ma_"), starts_with("dist_"), starts_with("drawdown_"),
               starts_with("fluxo_acum_"), starts_with("erro_"))
))

message(sprintf("  Obs totais       : %d", nrow(ds)))
message(sprintf("  Obs completas    : %d (%.1f%%)", n_complete, 100 * n_complete / nrow(ds)))

n_features_eng <- ds |>
  select(starts_with("ret_"), starts_with("vol_"), starts_with("spread_"),
         starts_with("ma_"), starts_with("dist_"), starts_with("max_"),
         starts_with("min_"), starts_with("drawdown_"), starts_with("range_"),
         starts_with("fluxo_acum_"), starts_with("erro_"),
         dia_semana, mes, trimestre, fim_de_mes, semana_do_ano,
         mes_copom, mes_fomc) |>
  ncol()

message(sprintf("  Features brutas  : %d (originais do model_dataset, exceto saldo_cambial)",
                ncol(ds) - n_features_eng - 1))  # -1 = date
message(sprintf("  Features eng.    : %d (criadas neste script)", n_features_eng))
message(sprintf("  Total de vars    : %d (incluindo targets)", ncol(ds)))

# ── Salvar ────────────────────────────────────────────────────────────────────

saveRDS(ds, here("data", "processed", "features_dataset.rds"))
message(sprintf("\n  -> data/processed/features_dataset.rds salvo"))

# ══════════════════════════════════════════════════════════════════════════════
# Diagnóstico — resumo das features engenheiradas
# ══════════════════════════════════════════════════════════════════════════════

section("Diagnóstico das features")

features_eng <- ds |>
  select(starts_with("ret_"), starts_with("vol_"), starts_with("spread_"),
         starts_with("ma_"), starts_with("dist_"), starts_with("max_"),
         starts_with("min_"), starts_with("drawdown_"), starts_with("range_"),
         starts_with("fluxo_acum_"), starts_with("erro_"),
         dia_semana, mes, trimestre, fim_de_mes, semana_do_ano,
         mes_copom, mes_fomc)

# Sumário de completude
completude <- features_eng |>
  summarise(across(everything(), ~ mean(!is.na(.x)))) |>
  pivot_longer(everything(), names_to = "feature", values_to = "pct_disponivel") |>
  arrange(pct_disponivel)

write_csv(completude, here("outputs", "tables", "fe-feature-completude.csv"))

# Features com < 80% de cobertura — candidatas à remoção ou tratamento
baixa_cobertura <- completude |> filter(pct_disponivel < 0.80)
if (nrow(baixa_cobertura) > 0) {
  message("\n  Features com < 80% de cobertura (avaliar remoção):")
  print(baixa_cobertura)
}

# Correlação das features com target_30d (referência)
features_para_cor <- features_eng |>
  bind_cols(ds |> select(target_5d, target_30d, target_90d)) |>
  select(where(is.numeric))

cor_result <- map_dfr(names(features_eng), function(feat) {
  df_pair <- features_para_cor |> select(all_of(feat), target_30d) |> drop_na()
  if (nrow(df_pair) < 50) return(NULL)
  tibble(
    feature  = feat,
    cor_t30  = cor(df_pair[[feat]], df_pair$target_30d, use = "complete.obs"),
    n        = nrow(df_pair)
  )
}) |>
  arrange(desc(abs(cor_t30)))

write_csv(cor_result, here("outputs", "tables", "fe-correlation-features.csv"))

message("\n  Top 20 features por |cor| com target_30d:")
cor_result |> slice_head(n = 20) |> print()

# ── Resumo escrito ─────────────────────────────────────────────────────────────

section("Resumo final")

grupos_summary <- tibble::tribble(
  ~grupo, ~n_features, ~descricao,
  "G1 — Retornos e Momentum USD/BRL",   14L, "ret_usd_*, ma_usd_*, dist_ma_*, drawdown/range_63d",
  "G2 — Volatilidade Realizada",          6L, "vol_usd_*d, vol_ratio, vol_vix_21d",
  "G3 — Spreads Macrofinanceiros",       10L, "spread_selic_fed, spread_10y_2y, spread_ipca_cpi, fluxo_acum, ewz",
  "G4 — Retornos Externos",             16L, "ret_dxy, vix, oil, ferro, ouro, ibov, sp500, erro_focus",
  "G5 — Calendário",                     8L, "dia_semana, mes, fim_de_mes, copom/fomc proxies"
)

summary_lines <- c(
  "══════════════════════════════════════════════════════════",
  "  Feature Engineering dolaR — Resumo",
  "══════════════════════════════════════════════════════════",
  sprintf("  Dataset de saída: %d obs x %d vars", nrow(ds), ncol(ds)),
  sprintf("  Features eng. criadas: %d", n_features_eng),
  "",
  "  Por grupo:",
  sprintf("  G1  Retornos/Momentum    14 features"),
  sprintf("  G2  Volatilidade          6 features"),
  sprintf("  G3  Spreads Macro        10 features"),
  sprintf("  G4  Retornos Externos    16 features"),
  sprintf("  G5  Calendário            8 features"),
  "",
  "  Descartada: saldo_cambial (<14 obs úteis)",
  "  Atenção: us_hy_spread (cobertura ~2023-07+), pim_geral (gap desde 2022)",
  "  sofr: NAs antes 2018-04 — avaliar imputação vs remoção",
  "",
  "  Próximo passo: scripts/11-modeling.R",
  "══════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "10-fe-summary.txt"))
writeLines(as.character(Sys.time()), here("checkpoints", "05-feature-engineering.complete"))

message("\n  Fase 5 concluída → data/processed/features_dataset.rds")
message("  Próximo: scripts/11-modeling.R")
