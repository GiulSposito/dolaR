# Fase 8 — Test Set Evaluation
# Owner: Alan
# Input:  models/tuned/champion-target_*.rds   — modelos finais fittados
#         models/test_data.rds                  — test set (PRIMEIRA VEZ)
#         data/processed/features_dataset.rds   — para preditores
#         outputs/tables/tuning-results.csv     — RMSE de CV para comparação
# Output: outputs/tables/test-performance.csv
#         outputs/tables/test-predictions.csv
#         outputs/figures/eval-*.png
#         outputs/figures/vip-*.png
#         reports/13-evaluation-summary.txt
#         models/production/                    — artifacts prontos para deploy
#
# ATENÇÃO: Este script toca o test set pela PRIMEIRA E ÚNICA VEZ.
#          Nenhuma decisão de modelagem pode ser tomada com base nesses resultados.
#
# Métricas avaliadas (briefing seção 9):
#   9.1 Erro numérico: RMSE, MAE, R²
#   9.2 Acurácia direcional: % acerto sinal (sobe/cai)
#   9.3 Valor econômico: hit ratio e retorno cumulativo da estratégia simples

library(tidyverse)
library(lubridate)
library(here)
library(tidymodels)
library(vip)
library(patchwork)
library(scales)

section <- function(title) message(sprintf("\n══ %s ══", title))

dir.create(here("outputs", "tables"),         recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "figures"),        recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),                   recursive = TRUE, showWarnings = FALSE)
dir.create(here("models", "production"),      recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),               recursive = TRUE, showWarnings = FALSE)

# ── Carregar dados ─────────────────────────────────────────────────────────────

section("Carregando champions e test set [PRIMEIRA VEZ]")

ds <- readRDS(here("data", "processed", "features_dataset.rds")) |>
  arrange(date)

test_data <- readRDS(here("models", "test_data.rds")) |>
  arrange(date)

message(sprintf("  Test set: %d obs  (%s a %s)",
                nrow(test_data), min(test_data$date), max(test_data$date)))
message("  [AVISO] Test set tocado pela primeira e única vez neste script.")

# Mesmos preditores do baseline/tuning
colunas_excluir <- c(
  "date",
  c("target_5d", "target_30d", "target_90d"),
  grep("^dir_", names(ds), value = TRUE),
  "usd_brl_ptax", "usd_brl", "us_hy_spread"
)
colunas_excluir <- intersect(colunas_excluir, names(ds))
predictors_all  <- setdiff(names(ds), colunas_excluir)

targets <- c("target_5d", "target_30d", "target_90d")

# Carregar RMSE de CV para comparação
cv_rmse <- tryCatch(
  read_csv(here("outputs", "tables", "tuning-results.csv"),
           show_col_types = FALSE) |>
    filter(modelo == champion_lookup(horizonte)) |>
    select(horizonte, cv_rmse = rmse_tuned),
  error = function(e) NULL
)

# Helper: qual modelo é champion de cada horizonte
champion_map <- c(
  target_5d  = "enet",
  target_30d = "rf",
  target_90d = "xgb"
)

# ── Loop de avaliação por horizonte ──────────────────────────────────────────

all_preds   <- list()
all_metrics <- list()
all_vip     <- list()

for (target in targets) {

  section(sprintf("Avaliando: %s", target))

  # Carregar champion
  champion_path <- here("models", "tuned", sprintf("champion-%s.rds", target))
  if (!file.exists(champion_path)) {
    message(sprintf("  AVISO: %s não encontrado, pulando.", champion_path))
    next
  }
  champion_fit <- readRDS(champion_path)

  # Preparar test data com os preditores corretos
  test_h <- test_data |>
    select(date, all_of(predictors_all), all_of(target)) |>
    drop_na(all_of(target))

  message(sprintf("  Obs no test set com target válido: %d", nrow(test_h)))

  # ── Predições ────────────────────────────────────────────────────────────
  preds <- augment(champion_fit, new_data = test_h) |>
    select(date, actual = all_of(target), predicted = .pred) |>
    mutate(
      residual    = actual - predicted,
      abs_error   = abs(residual),
      sq_error    = residual^2,
      horizonte   = target,
      # Acurácia direcional: sinal previsto vs sinal real
      dir_actual  = sign(actual),
      dir_pred    = sign(predicted),
      dir_correct = (dir_actual == dir_pred)
    )

  all_preds[[target]] <- preds

  # ── Métricas numéricas (seção 9.1 do briefing) ───────────────────────────
  rmse_val  <- sqrt(mean(preds$sq_error, na.rm = TRUE))
  mae_val   <- mean(preds$abs_error, na.rm = TRUE)
  rsq_val   <- 1 - sum(preds$sq_error, na.rm = TRUE) /
                   sum((preds$actual - mean(preds$actual, na.rm = TRUE))^2, na.rm = TRUE)

  # Acurácia direcional (seção 9.2)
  dir_acc <- mean(preds$dir_correct, na.rm = TRUE)

  # Métricas econômicas simples (seção 9.3):
  # Estratégia: compra dólar se modelo prevê retorno > 0, vende se < 0
  # Retorno da estratégia = dir_pred × retorno_real
  preds <- preds |>
    mutate(
      strategy_ret = dir_pred * actual,   # long se pred>0, short se pred<0
      buyhold_ret  = actual               # compra e segura
    )

  strategy_cum  <- prod(1 + preds$strategy_ret, na.rm = TRUE) - 1
  buyhold_cum   <- prod(1 + preds$buyhold_ret,  na.rm = TRUE) - 1
  hit_ratio     <- mean(preds$strategy_ret > 0, na.rm = TRUE)

  # Comparação com CV
  cv_rmse_val <- tryCatch({
    read_csv(here("outputs", "tables", "tuning-results.csv"),
             show_col_types = FALSE) |>
      filter(horizonte == target, modelo == champion_map[target]) |>
      pull(rmse_tuned) |>
      first()
  }, error = function(e) NA_real_)

  metrics_row <- tibble(
    horizonte      = target,
    champion       = champion_map[target],
    n_obs          = nrow(preds),
    # 9.1 Erro numérico
    test_rmse      = rmse_val,
    test_mae       = mae_val,
    test_rsq       = rsq_val,
    cv_rmse        = cv_rmse_val,
    cv_vs_test_pct = round((test_rmse - cv_rmse_val) / cv_rmse_val * 100, 1),
    # 9.2 Direcional
    dir_accuracy   = dir_acc,
    # 9.3 Econômico
    strategy_return_cum = strategy_cum,
    buyhold_return_cum  = buyhold_cum,
    hit_ratio      = hit_ratio
  )

  all_metrics[[target]] <- metrics_row

  message(sprintf("  RMSE test   : %.5f  (CV: %.5f, diff: %+.1f%%)",
                  rmse_val, cv_rmse_val,
                  ifelse(is.na(cv_rmse_val), NA, (rmse_val - cv_rmse_val) / cv_rmse_val * 100)))
  message(sprintf("  MAE  test   : %.5f", mae_val))
  message(sprintf("  R²   test   : %.4f", rsq_val))
  message(sprintf("  Dir accuracy: %.1f%%", dir_acc * 100))
  message(sprintf("  Hit ratio   : %.1f%%  (estratégia simples)", hit_ratio * 100))
  message(sprintf("  Ret. estrat.: %+.2f%%  |  Buy&Hold: %+.2f%%",
                  strategy_cum * 100, buyhold_cum * 100))

  # ── VIP (feature importance) ─────────────────────────────────────────────
  vip_data <- tryCatch({
    model_engine <- extract_fit_parsnip(champion_fit)

    if (champion_map[target] == "enet") {
      # glmnet: coeficientes absolutos como importância
      coefs <- coef(model_engine$fit, s = model_engine$fit$lambda[
        which.min(abs(model_engine$fit$lambda - model_engine$spec$args$penalty[[2]]))
      ]) |>
        as.matrix() |>
        as.data.frame() |>
        rownames_to_column("Variable") |>
        filter(Variable != "(Intercept)") |>
        rename(Importance = s1) |>
        mutate(Importance = abs(Importance)) |>
        arrange(desc(Importance)) |>
        slice_head(n = 20)
    } else {
      # ranger / xgboost: importância nativa
      vi(model_engine, num_features = 20) |>
        arrange(desc(Importance))
    }
  }, error = function(e) {
    message(sprintf("  VIP indisponível para %s: %s", target, e$message))
    NULL
  })

  if (!is.null(vip_data)) {
    all_vip[[target]] <- vip_data

    p_vip <- vip_data |>
      slice_head(n = 20) |>
      ggplot(aes(x = reorder(Variable, Importance), y = Importance)) +
      geom_col(fill = "#2E86AB", alpha = 0.85) +
      coord_flip() +
      labs(
        title    = sprintf("Feature Importance — %s (%s)",
                           str_remove(target, "target_"), champion_map[target]),
        subtitle = "Importância nativa do modelo (impurity / coeficiente absoluto)",
        x = NULL, y = "Importância"
      ) +
      theme_minimal(base_size = 11)

    ggsave(
      here("outputs", "figures", sprintf("vip-%s.png", target)),
      plot = p_vip, width = 10, height = 7, dpi = 150
    )
    message(sprintf("  -> outputs/figures/vip-%s.png salvo", target))
  }
}

# ── Consolidar e salvar métricas ──────────────────────────────────────────────

section("Consolidando métricas de teste")

metrics_all <- bind_rows(all_metrics)
preds_all   <- bind_rows(all_preds)

write_csv(metrics_all, here("outputs", "tables", "test-performance.csv"))
write_csv(preds_all,   here("outputs", "tables", "test-predictions.csv"))

message("\n  Resumo de performance no test set:")
metrics_all |>
  select(horizonte, champion, n_obs, test_rmse, test_mae, test_rsq,
         cv_rmse, cv_vs_test_pct, dir_accuracy, hit_ratio) |>
  print()

# ── Gráficos de avaliação ─────────────────────────────────────────────────────

section("Gerando gráficos de avaliação")

# 1. Predicted vs Actual por horizonte
p_pred_actual <- preds_all |>
  mutate(horizonte = factor(str_remove(horizonte, "target_"),
                            levels = c("5d", "30d", "90d"))) |>
  ggplot(aes(x = predicted, y = actual)) +
  geom_point(alpha = 0.35, size = 1.5, color = "#2E86AB") +
  geom_abline(slope = 1, intercept = 0, color = "#E84855",
              linetype = "dashed", linewidth = 0.8) +
  geom_smooth(method = "lm", se = TRUE, color = "#444444",
              linewidth = 0.6, alpha = 0.15) +
  facet_wrap(~ horizonte, scales = "free", ncol = 3) +
  labs(
    title    = "Previsto vs Real — Test Set",
    subtitle = "Linha vermelha = predição perfeita. Cinza = ajuste linear real.",
    x = "Previsto (retorno log)", y = "Real (retorno log)"
  ) +
  theme_minimal(base_size = 12) +
  theme(strip.text = element_text(face = "bold"))

ggsave(here("outputs", "figures", "eval-pred-vs-actual.png"),
       p_pred_actual, width = 13, height = 5, dpi = 150)

# 2. Série temporal de erros
p_residuals <- preds_all |>
  mutate(horizonte = factor(str_remove(horizonte, "target_"),
                            levels = c("5d", "30d", "90d"))) |>
  ggplot(aes(x = date, y = residual)) +
  geom_hline(yintercept = 0, color = "#E84855",
             linetype = "dashed", linewidth = 0.7) +
  geom_line(alpha = 0.5, color = "#2E86AB", linewidth = 0.4) +
  geom_smooth(se = FALSE, color = "#444444",
              linewidth = 0.8, method = "loess", span = 0.3) +
  facet_wrap(~ horizonte, scales = "free_y", ncol = 1) +
  labs(
    title    = "Resíduos ao longo do tempo — Test Set (2022-11 a 2026-02)",
    subtitle = "Linha cinza = tendência dos resíduos. Desvio sistemático indica regime-break.",
    x = NULL, y = "Resíduo (retorno log)"
  ) +
  theme_minimal(base_size = 12) +
  theme(strip.text = element_text(face = "bold"))

ggsave(here("outputs", "figures", "eval-residuals-time.png"),
       p_residuals, width = 13, height = 9, dpi = 150)

# 3. Retorno cumulativo: estratégia vs buy&hold
p_strategy <- preds_all |>
  mutate(horizonte = factor(str_remove(horizonte, "target_"),
                            levels = c("5d", "30d", "90d"))) |>
  group_by(horizonte) |>
  arrange(date) |>
  mutate(
    cum_strategy = cumprod(1 + dir_pred * actual) - 1,
    cum_buyhold  = cumprod(1 + actual) - 1
  ) |>
  ungroup() |>
  pivot_longer(cols = c(cum_strategy, cum_buyhold),
               names_to = "estrategia", values_to = "retorno_cum") |>
  mutate(estrategia = recode(estrategia,
                             cum_strategy = "Estratégia (modelo)",
                             cum_buyhold  = "Buy & Hold")) |>
  ggplot(aes(x = date, y = retorno_cum, color = estrategia)) +
  geom_line(linewidth = 0.8) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
  facet_wrap(~ horizonte, scales = "free_y", ncol = 3) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_color_manual(values = c("Estratégia (modelo)" = "#2E86AB",
                                "Buy & Hold"          = "#E84855")) +
  labs(
    title    = "Retorno cumulativo — Estratégia simples (long/short) vs Buy & Hold",
    subtitle = "Test set. Estratégia: longa se pred>0, curta se pred<0. Sem custos de transação.",
    x = NULL, y = "Retorno cumulativo", color = NULL
  ) +
  theme_minimal(base_size = 12) +
  theme(strip.text  = element_text(face = "bold"),
        legend.position = "top")

ggsave(here("outputs", "figures", "eval-strategy-returns.png"),
       p_strategy, width = 13, height = 5, dpi = 150)

message("  -> outputs/figures/eval-pred-vs-actual.png")
message("  -> outputs/figures/eval-residuals-time.png")
message("  -> outputs/figures/eval-strategy-returns.png")

# ── Artefatos de produção ────────────────────────────────────────────────────

section("Copiando artefatos para production/")

for (target in targets) {
  src <- here("models", "tuned", sprintf("champion-%s.rds", target))
  dst <- here("models", "production", sprintf("model-%s.rds", target))
  if (file.exists(src)) {
    file.copy(src, dst, overwrite = TRUE)
    message(sprintf("  -> %s copiado", basename(dst)))
  }
}

write_csv(metrics_all,
          here("models", "production", "performance-summary.csv"))

# ── Relatório final ───────────────────────────────────────────────────────────

section("Escrevendo relatório final")

# Benchmark ARIMA D+5 para referência
arima_5d <- 0.01570

summary_lines <- c(
  "══════════════════════════════════════════════════════════════════",
  "  AVALIAÇÃO FINAL NO TEST SET — dolaR",
  "══════════════════════════════════════════════════════════════════",
  sprintf("  Período test set : %s a %s  (%d obs)",
          min(test_data$date), max(test_data$date), nrow(test_data)),
  "  Modelos avaliados: champion de cada horizonte (fit em train_val)",
  "",
  "  ── Métricas numéricas (9.1) ──────────────────────────────────",
  paste0("  ", capture.output(
    metrics_all |>
      mutate(horizonte = str_remove(horizonte, "target_")) |>
      select(horizonte, champion, test_rmse, cv_rmse,
             cv_vs_test_pct, test_mae, test_rsq) |>
      print()
  )),
  "",
  "  ── Acurácia direcional (9.2) ─────────────────────────────────",
  paste0("  ", capture.output(
    metrics_all |>
      mutate(horizonte = str_remove(horizonte, "target_")) |>
      select(horizonte, dir_accuracy, hit_ratio) |>
      mutate(across(c(dir_accuracy, hit_ratio), ~ scales::percent(., accuracy = 0.1))) |>
      print()
  )),
  "",
  "  ── Valor econômico (9.3) ─────────────────────────────────────",
  paste0("  ", capture.output(
    metrics_all |>
      mutate(horizonte = str_remove(horizonte, "target_")) |>
      select(horizonte, strategy_return_cum, buyhold_return_cum) |>
      mutate(across(c(strategy_return_cum, buyhold_return_cum),
                    ~ scales::percent(., accuracy = 0.1))) |>
      print()
  )),
  "",
  sprintf("  ── Referência ARIMA D+5 (CV) : %.5f ──────────────────────", arima_5d),
  "",
  "  Arquivos gerados:",
  "  - outputs/tables/test-performance.csv",
  "  - outputs/tables/test-predictions.csv",
  "  - outputs/figures/eval-pred-vs-actual.png",
  "  - outputs/figures/eval-residuals-time.png",
  "  - outputs/figures/eval-strategy-returns.png",
  "  - outputs/figures/vip-target_*.png",
  "  - models/production/model-target_*.rds",
  "",
  "  Fase 8 concluída. Pipeline de modelagem completo.",
  "══════════════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "13-evaluation-summary.txt"))
writeLines(as.character(Sys.time()),
           here("checkpoints", "08-evaluation.complete"))

message("\n  Fase 8 concluída → outputs/ + models/production/")
