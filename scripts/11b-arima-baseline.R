# Fase 6b — ARIMA Baseline
# Owner: Alan
# Input:  data/processed/features_dataset.rds
#         models/test_data.rds            — para confirmar corte
# Output: outputs/tables/arima-cv-results.csv
#         outputs/tables/baseline-cv-results-full.csv  (ML + ARIMA unificado)
#         outputs/figures/baseline-comparison-full.png
#         reports/11b-arima-summary.txt
#
# Estratégia:
#   - ARIMA univariado sobre a série de retornos log do USD/BRL (ret_usd_1d)
#   - auto.arima por fold — permite que a ordem mude conforme a janela
#   - Previsão multi-step: h=5, h=30, h=90 dias à frente
#   - Mesmo corte 80/20 e mesma lógica walk-forward do script 11
#
# Por que ARIMA univariado?
#   O briefing pede ARIMA como baseline "simples" (seção 6.1 + Etapa 1 MVP).
#   ARIMA univariado é o benchmark clássico de autocorrelação — se modelos ML
#   não batem ARIMA, o sinal macrofinanceiro não está sendo capturado.
#
# Nota sobre previsão multi-step:
#   Para D+30 e D+90, somamos as previsões passo-a-passo (h=1 cumulativo).
#   O target é retorno log acumulado entre t e t+H, logo:
#   target_Hd = sum(ret_1d_t+1 ... ret_1d_t+H)  ≈ forecast::forecast(h=H) somado.

library(tidyverse)
library(lubridate)
library(here)
library(forecast)
library(slider)

section <- function(title) message(sprintf("\n══ %s ══", title))

dir.create(here("outputs", "tables"),  recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),            recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),        recursive = TRUE, showWarnings = FALSE)

# ── Carregar dados ─────────────────────────────────────────────────────────────

section("Carregando dados")
ds <- readRDS(here("data", "processed", "features_dataset.rds")) |>
  arrange(date)

# Mesmo corte do script 11
n_total <- nrow(ds)
n_test  <- floor(n_total * 0.20)
n_train <- n_total - n_test
cutoff  <- ds$date[n_train]

train_val <- ds |> filter(date <= cutoff)

message(sprintf("  Train+Val : %d obs  (%s a %s)",
                nrow(train_val), min(train_val$date), max(train_val$date)))
message(sprintf("  Corte     : %s  (test set intocado)", cutoff))

# Série de retornos log diários (univariada)
ret_series <- train_val |>
  select(date, ret_usd_1d) |>
  drop_na()

message(sprintf("  Série ret_usd_1d: %d obs com valor", nrow(ret_series)))

# ── Parâmetros do walk-forward ─────────────────────────────────────────────────
#
# Mesma lógica do sliding_window do script 11:
#   lookback  = 756 obs de treino
#   step      = 63  (avança 1 trimestre por vez)
#   assess    = 63  (avalia 1 trimestre à frente)
#
# Para ARIMA, construímos os folds manualmente porque forecast::forecast
# não integra com rsample nativamente.

lookback <- 756L
step_sz  <- 63L
assess   <- 63L

n_series <- nrow(ret_series)
starts   <- seq(1L, n_series - lookback - assess + 1L, by = step_sz)
starts   <- starts[starts + lookback + assess - 1L <= n_series]

message(sprintf("  Walk-forward folds: %d", length(starts)))

# Horizontes de previsão
horizons <- c(5L, 30L, 90L)
horizon_names <- c("target_5d", "target_30d", "target_90d")

# ── Walk-forward ARIMA ────────────────────────────────────────────────────────

section("Rodando ARIMA walk-forward (auto.arima por fold)")

set.seed(42)
results_list <- vector("list", length(starts))

pb_total <- length(starts)
for (i in seq_along(starts)) {

  idx_train <- starts[i]:(starts[i] + lookback - 1L)
  idx_assess <- (starts[i] + lookback):(starts[i] + lookback + assess - 1L)

  # Garantir que índices estão dentro do range
  if (max(idx_assess) > n_series) next

  train_ret <- ret_series$ret_usd_1d[idx_train]
  assess_rows <- ret_series[idx_assess, ]

  # Ajustar auto.arima na janela de treino
  # max.p/q limitados para velocidade — câmbio raramente precisa de ordens altas
  fit <- tryCatch(
    auto.arima(
      train_ret,
      max.p = 5, max.q = 5, max.P = 1, max.Q = 1,
      stationary = TRUE,   # ret_usd_1d já é estacionário
      seasonal   = FALSE,  # sem sazonalidade em retornos diários
      stepwise   = TRUE,   # mais rápido
      approximation = TRUE
    ),
    error = function(e) NULL
  )

  if (is.null(fit)) next

  # Previsão h=90 passos (cobre todos os horizontes de uma vez)
  fc <- tryCatch(
    forecast(fit, h = max(horizons)),
    error = function(e) NULL
  )

  if (is.null(fc)) next

  # Retornos previstos acumulados para cada horizonte
  # target_Hd = sum dos retornos diários de t+1 até t+H
  pred_cumulative <- cumsum(as.numeric(fc$mean))

  # Retornos reais acumulados (usando ret_usd_1d da janela de assessment)
  # Para cada horizonte H, precisamos dos próximos H dias a partir do fim do treino
  real_cumulative <- cumsum(assess_rows$ret_usd_1d)

  # Montar linha de resultado para cada horizonte
  fold_results <- map_dfr(seq_along(horizons), function(j) {
    h <- horizons[j]
    tgt_name <- horizon_names[j]

    # Usar o valor real do target do dataset (já calculado corretamente)
    # Pegar a obs no dataset original que corresponde ao fim desta janela de assess
    end_idx_in_ds <- which(ds$date == assess_rows$date[min(h, nrow(assess_rows))])

    real_val <- if (length(end_idx_in_ds) > 0 && !is.na(ds[[tgt_name]][end_idx_in_ds])) {
      ds[[tgt_name]][end_idx_in_ds]
    } else if (h <= length(real_cumulative)) {
      real_cumulative[h]
    } else {
      NA_real_
    }

    pred_val <- if (h <= length(pred_cumulative)) pred_cumulative[h] else NA_real_

    tibble(
      fold      = i,
      horizonte = tgt_name,
      h_dias    = h,
      date_end  = assess_rows$date[min(h, nrow(assess_rows))],
      predicted = pred_val,
      actual    = real_val,
      arima_order = paste0("ARIMA(", paste(arimaorder(fit), collapse=","), ")")
    )
  })

  results_list[[i]] <- fold_results

  if (i %% 10 == 0 || i == pb_total) {
    message(sprintf("  Fold %d/%d — %s", i, pb_total, fit$arima$coef |> names() |> head(1)))
  }
}

arima_preds <- bind_rows(results_list) |> drop_na(predicted, actual)

message(sprintf("  Previsões geradas: %d", nrow(arima_preds)))

# ── Calcular métricas por horizonte ──────────────────────────────────────────

section("Calculando métricas ARIMA")

arima_metrics <- arima_preds |>
  group_by(horizonte) |>
  summarise(
    rmse     = sqrt(mean((predicted - actual)^2, na.rm = TRUE)),
    mae      = mean(abs(predicted - actual), na.rm = TRUE),
    # R² manual (pode ser negativo se pior que a média)
    rsq      = 1 - sum((predicted - actual)^2, na.rm = TRUE) /
                   sum((actual - mean(actual, na.rm = TRUE))^2, na.rm = TRUE),
    n_folds  = n(),
    .groups  = "drop"
  ) |>
  mutate(
    wflow_id = "arima",
    modelo   = "arima"
  )

message("\n  Métricas ARIMA:")
print(arima_metrics |> select(horizonte, rmse, mae, rsq, n_folds))

write_csv(arima_preds,   here("outputs", "tables", "arima-cv-predictions.csv"))
write_csv(arima_metrics, here("outputs", "tables", "arima-cv-results.csv"))
message("  -> outputs/tables/arima-cv-results.csv salvo")

# ── Comparação unificada ML + ARIMA ──────────────────────────────────────────

section("Consolidando comparação ML + ARIMA")

# Carregar resultados do script 11
ml_results_path <- here("outputs", "tables", "baseline-cv-results.csv")
if (!file.exists(ml_results_path)) {
  stop("Arquivo baseline-cv-results.csv não encontrado. Rode 11-modeling.R primeiro.")
}

ml_metrics <- read_csv(ml_results_path, show_col_types = FALSE) |>
  filter(.metric == "rmse") |>
  select(horizonte, wflow_id, rmse_mean = mean, rmse_se = std_err) |>
  mutate(
    modelo    = str_remove(wflow_id, "rec_"),
    horizonte = str_remove(horizonte, "target_")  # já vem sem "target_" aqui
  )

# Verificar formato do horizonte na coluna
# (pode vir como "target_5d" ou "5d" dependendo do read_csv)
if (all(grepl("^target_", ml_metrics$horizonte))) {
  ml_metrics <- ml_metrics |> mutate(horizonte = str_remove(horizonte, "target_"))
}

arima_for_compare <- arima_metrics |>
  mutate(
    horizonte = str_remove(horizonte, "target_"),
    rmse_mean = rmse,
    rmse_se   = NA_real_
  ) |>
  select(horizonte, wflow_id, modelo, rmse_mean, rmse_se)

full_compare <- bind_rows(ml_metrics, arima_for_compare) |>
  arrange(horizonte, rmse_mean)

write_csv(full_compare, here("outputs", "tables", "baseline-cv-results-full.csv"))
message("  -> outputs/tables/baseline-cv-results-full.csv salvo")

# Tabela resumo
message("\n  Ranking completo (RMSE walk-forward CV):")
full_compare |>
  select(horizonte, modelo, rmse_mean) |>
  pivot_wider(names_from = horizonte, values_from = rmse_mean) |>
  arrange(`5d`) |>
  print()

# ── Gráfico comparação completa ───────────────────────────────────────────────

section("Gerando gráfico de comparação completo")

p_full <- full_compare |>
  mutate(
    horizonte = factor(horizonte, levels = c("5d", "30d", "90d")),
    modelo    = factor(modelo,
                       levels = full_compare |>
                         filter(horizonte == "30d") |>
                         arrange(rmse_mean) |>
                         pull(modelo) |>
                         unique())
  ) |>
  ggplot(aes(x = reorder(modelo, rmse_mean), y = rmse_mean,
             color = modelo == "null", shape = modelo == "arima")) +
  geom_point(size = 3.5) +
  geom_errorbar(
    aes(ymin = rmse_mean - rmse_se, ymax = rmse_mean + rmse_se),
    width = 0.25, na.rm = TRUE
  ) +
  geom_hline(
    data = full_compare |>
      filter(modelo == "null") |>
      mutate(horizonte = factor(horizonte, levels = c("5d", "30d", "90d"))),
    aes(yintercept = rmse_mean),
    linetype = "dashed", color = "gray50", linewidth = 0.5
  ) +
  coord_flip() +
  facet_wrap(~ horizonte, scales = "free_x", ncol = 3) +
  scale_color_manual(values = c("FALSE" = "#2E86AB", "TRUE" = "#E84855"),
                     guide = "none") +
  scale_shape_manual(values = c("FALSE" = 16, "TRUE" = 17), guide = "none") +
  labs(
    title    = "Baseline completo — dolaR (ML + ARIMA)",
    subtitle = "RMSE walk-forward CV. Linha tracejada = random walk. Triângulo = ARIMA.",
    x        = NULL,
    y        = "RMSE (retorno log)",
    caption  = "Modelos com defaults. Tuning no próximo passo."
  ) +
  theme_minimal(base_size = 12) +
  theme(strip.text = element_text(face = "bold"))

ggsave(
  here("outputs", "figures", "baseline-comparison-full.png"),
  plot   = p_full,
  width  = 13, height = 5, dpi = 150
)
message("  -> outputs/figures/baseline-comparison-full.png salvo")

# ── Relatório final ────────────────────────────────────────────────────────────

section("Escrevendo relatório")

null_rmse <- full_compare |> filter(modelo == "null") |>
  select(horizonte, null_rmse = rmse_mean)

arima_vs_null <- arima_metrics |>
  mutate(horizonte = str_remove(horizonte, "target_")) |>
  left_join(null_rmse, by = "horizonte") |>
  mutate(vs_null_pct = round((rmse / null_rmse - 1) * 100, 1))

summary_lines <- c(
  "══════════════════════════════════════════════════════════",
  "  ARIMA Baseline dolaR — Resumo",
  "══════════════════════════════════════════════════════════",
  "",
  "  ARIMA (auto) vs Null (random walk):",
  paste0("  ", capture.output(
    arima_vs_null |>
      select(horizonte, arima_rmse = rmse, null_rmse, vs_null_pct) |>
      print()
  )),
  "",
  "  Ranking completo RMSE por horizonte:",
  paste0("  ", capture.output(
    full_compare |>
      select(horizonte, modelo, rmse_mean) |>
      pivot_wider(names_from = horizonte, values_from = rmse_mean) |>
      arrange(`5d`) |>
      print()
  )),
  "",
  "  Arquivos gerados:",
  "  - outputs/tables/arima-cv-results.csv",
  "  - outputs/tables/arima-cv-predictions.csv",
  "  - outputs/tables/baseline-cv-results-full.csv",
  "  - outputs/figures/baseline-comparison-full.png",
  "",
  "  Próximo passo: scripts/12-tuning.R",
  "══════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "11b-arima-summary.txt"))
writeLines(as.character(Sys.time()),
           here("checkpoints", "06b-arima-baseline.complete"))

message("\n  Fase 6b concluída → outputs/tables/baseline-cv-results-full.csv")
message("  Próximo: scripts/12-tuning.R")
