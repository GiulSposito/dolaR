# Fase 7 — Hyperparameter Tuning
# Owner: Alan
# Input:  data/processed/features_dataset.rds
#         models/test_data.rds            — confirmar corte (NÃO usar)
# Output: models/tuned/                  — workflow finalizado por horizonte
#         outputs/tables/tuning-results.csv
#         outputs/figures/tuning-comparison.png
#         reports/12-tuning-summary.txt
#
# Candidatos por baseline (script 11 + 11b):
#   D+5  → Elastic Net (0.0209) + Random Forest (0.0224)
#          [ARIMA venceu com 0.0157 — benchmark de referência]
#   D+30 → Random Forest (0.0491) + XGBoost (0.0543)
#   D+90 → Random Forest (0.0690) + XGBoost (0.0764)
#
# Estratégia: tune_grid com Latin Hypercube (30 configs por modelo)
#   - Mesmo walk-forward CV do baseline (sliding_window, 39 folds)
#   - Otimizar RMSE como métrica primária
#   - Salvar melhor workflow por horizonte (champion)
#
# finetune não instalado → tune_grid com LHC é suficiente para 2-3 parâmetros.

library(tidyverse)
library(lubridate)
library(here)
library(tidymodels)
library(slider)
library(future)

plan(multisession, workers = max(1L, parallel::detectCores() - 1L))
options(future.globals.maxSize = 2 * 1024^3)

section <- function(title) message(sprintf("\n══ %s ══", title))

dir.create(here("models", "tuned"),     recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "tables"),   recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "figures"),  recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),             recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),         recursive = TRUE, showWarnings = FALSE)

# ── Carregar dados ─────────────────────────────────────────────────────────────

section("Carregando dados")
ds <- readRDS(here("data", "processed", "features_dataset.rds")) |>
  arrange(date)

n_total <- nrow(ds)
n_test  <- floor(n_total * 0.20)
n_train <- n_total - n_test
cutoff  <- ds$date[n_train]

train_val <- ds |> filter(date <= cutoff)

message(sprintf("  Train+Val : %d obs  (%s a %s)",
                nrow(train_val), min(train_val$date), max(train_val$date)))
message(sprintf("  Corte     : %s  (test set intocado)", cutoff))

# Mesmos preditores do baseline
colunas_excluir <- c(
  "date",
  c("target_5d", "target_30d", "target_90d"),
  grep("^dir_", names(ds), value = TRUE),
  "usd_brl_ptax", "usd_brl", "us_hy_spread"
)
colunas_excluir <- intersect(colunas_excluir, names(ds))
predictors_all  <- setdiff(names(ds), colunas_excluir)

# ── Walk-forward CV (idêntico ao baseline) ────────────────────────────────────

section("Recriando walk-forward CV")

wf_folds <- rsample::sliding_window(
  train_val,
  lookback     = 756L,
  step         = 63L,
  assess_start = 1L,
  assess_stop  = 63L
)
message(sprintf("  %d folds", nrow(wf_folds)))

# ── Recipe (mesma lógica do baseline) ────────────────────────────────────────

make_recipe <- function(target, data) {
  recipe(as.formula(paste(target, "~ .")), data = data) |>
    step_zv(all_predictors()) |>
    step_nzv(all_predictors(), freq_cut = 95 / 5) |>
    step_impute_median(all_numeric_predictors()) |>
    step_normalize(all_numeric_predictors())
}

cv_metrics <- yardstick::metric_set(
  yardstick::rmse,
  yardstick::mae,
  yardstick::rsq
)

# ── Especificações de tuning ──────────────────────────────────────────────────

# Elastic Net — 2 parâmetros: penalty + mixture
enet_tune_spec <- linear_reg(
  penalty = tune(),
  mixture = tune()
) |>
  set_engine("glmnet") |>
  set_mode("regression")

# Random Forest — 2 parâmetros: mtry + min_n (trees fixo em 500)
rf_tune_spec <- rand_forest(
  mtry  = tune(),
  min_n = tune(),
  trees = 500L
) |>
  set_engine("ranger", importance = "impurity", num.threads = 1L) |>
  set_mode("regression")

# XGBoost — 4 parâmetros: tree_depth, min_n, learn_rate, mtry
xgb_tune_spec <- boost_tree(
  trees      = 300L,
  tree_depth = tune(),
  min_n      = tune(),
  learn_rate = tune(),
  mtry       = tune()
) |>
  set_engine("xgboost", nthread = 1L) |>
  set_mode("regression")

# ── Configurações por horizonte ───────────────────────────────────────────────
#
# D+5  → enet + rf
# D+30 → rf + xgb
# D+90 → rf + xgb

horizon_config <- list(
  target_5d = list(
    models = list(enet = enet_tune_spec, rf = rf_tune_spec)
  ),
  target_30d = list(
    models = list(rf = rf_tune_spec, xgb = xgb_tune_spec)
  ),
  target_90d = list(
    models = list(rf = rf_tune_spec, xgb = xgb_tune_spec)
  )
)

# ── Loop de tuning ────────────────────────────────────────────────────────────

all_tuning  <- list()
all_best    <- list()
champions   <- list()

for (target in names(horizon_config)) {

  section(sprintf("Horizonte: %s", target))

  data_h  <- train_val |> select(all_of(predictors_all), all_of(target))
  rec     <- make_recipe(target, data_h)
  n_pred  <- rec |> prep() |> bake(new_data = NULL) |>
    select(-all_of(target)) |> ncol()

  message(sprintf("  Preditores após recipe: %d", n_pred))

  model_specs <- horizon_config[[target]]$models
  tuning_h    <- list()
  best_h      <- list()

  for (mod_name in names(model_specs)) {

    message(sprintf("\n  -- Tuning: %s --", mod_name))

    spec <- model_specs[[mod_name]]

    # Grid Latin Hypercube — 30 configurações
    # Para rf e enet: mtry limitado ao n_pred real
    if (mod_name == "rf") {
      param_set <- parameters(
        mtry(range  = c(max(2L, floor(sqrt(n_pred))),
                        min(n_pred, floor(n_pred * 0.5)))),
        min_n(range = c(2L, 30L))
      )
    } else if (mod_name == "enet") {
      param_set <- parameters(
        penalty(range = c(-5, 0), trans = scales::log10_trans()),
        mixture(range = c(0, 1))
      )
    } else {  # xgb
      param_set <- parameters(
        tree_depth(range = c(3L, 10L)),
        min_n(range      = c(3L, 30L)),
        learn_rate(range = c(-2.5, -0.5), trans = scales::log10_trans()),
        mtry(range       = c(max(2L, floor(sqrt(n_pred))),
                             min(n_pred, floor(n_pred * 0.4))))
      )
    }

    set.seed(42)
    lhc_grid <- grid_latin_hypercube(param_set, size = 20L)

    wf_tune <- workflow() |>
      add_recipe(rec) |>
      add_model(spec)

    tstart <- proc.time()

    tune_res <- tryCatch(
      tune_grid(
        wf_tune,
        resamples = wf_folds,
        grid      = lhc_grid,
        metrics   = cv_metrics,
        control   = control_grid(
          save_pred     = FALSE,
          save_workflow = TRUE,
          verbose       = FALSE,
          allow_par     = TRUE,
          parallel_over = "resamples"
        )
      ),
      error = function(e) { message("  ERRO: ", e$message); NULL }
    )

    elapsed <- round((proc.time() - tstart)[["elapsed"]], 1)
    message(sprintf("  Concluído em %.1fs", elapsed))

    if (is.null(tune_res)) next

    tuning_h[[mod_name]] <- tune_res

    # Melhor configuração
    best_params <- select_best(tune_res, metric = "rmse")
    best_rmse   <- show_best(tune_res, metric = "rmse", n = 1)

    message(sprintf("  Melhor RMSE: %.5f (± %.5f)",
                    best_rmse$mean, best_rmse$std_err))
    message("  Melhores params:")
    print(best_params)

    best_h[[mod_name]] <- list(
      tune_result  = tune_res,
      best_params  = best_params,
      best_rmse    = best_rmse$mean,
      best_rmse_se = best_rmse$std_err,
      wf_finalized = finalize_workflow(wf_tune, best_params)
    )
  }

  all_tuning[[target]] <- tuning_h
  all_best[[target]]   <- best_h

  # Champion deste horizonte = menor RMSE entre os modelos tunados
  rmse_by_model <- map_dbl(best_h, ~ .x$best_rmse)
  champion_name <- names(which.min(rmse_by_model))

  message(sprintf("\n  Champion %s → %s (RMSE = %.5f)",
                  target, champion_name, min(rmse_by_model)))

  champion_wf <- best_h[[champion_name]]$wf_finalized

  # Fit final do champion sobre TODO o train_val
  message("  Fittando champion em train_val completo...")
  champion_fit <- champion_wf |> fit(data = data_h)

  saveRDS(champion_fit,
          here("models", "tuned", sprintf("champion-%s.rds", target)))
  saveRDS(champion_wf,
          here("models", "tuned", sprintf("champion-wf-%s.rds", target)))

  champions[[target]] <- list(
    model    = champion_name,
    rmse_cv  = min(rmse_by_model),
    fit      = champion_fit,
    workflow = champion_wf
  )
}

plan(sequential)

# ── Consolidar resultados ─────────────────────────────────────────────────────

section("Consolidando resultados de tuning")

tuning_summary <- map_dfr(names(all_best), function(tgt) {
  map_dfr(names(all_best[[tgt]]), function(mod) {
    b <- all_best[[tgt]][[mod]]
    tibble(
      horizonte    = tgt,
      modelo       = mod,
      rmse_tuned   = b$best_rmse,
      rmse_tuned_se = b$best_rmse_se
    )
  })
})

# Carregar RMSE do baseline para comparação
baseline_path <- here("outputs", "tables", "baseline-cv-results-full.csv")
if (file.exists(baseline_path)) {
  baseline_rmse <- read_csv(baseline_path, show_col_types = FALSE) |>
    mutate(horizonte = paste0("target_", horizonte)) |>
    select(horizonte, modelo, rmse_baseline = rmse_mean)

  tuning_summary <- tuning_summary |>
    left_join(baseline_rmse, by = c("horizonte", "modelo")) |>
    mutate(
      melhora_pct = round((rmse_baseline - rmse_tuned) / rmse_baseline * 100, 2)
    )
}

write_csv(tuning_summary, here("outputs", "tables", "tuning-results.csv"))
message("  -> outputs/tables/tuning-results.csv salvo")

message("\n  Resumo de melhoria pós-tuning:")
print(tuning_summary)

# ── Tabela champion ───────────────────────────────────────────────────────────

champion_table <- map_dfr(names(champions), function(tgt) {
  tibble(
    horizonte  = tgt,
    champion   = champions[[tgt]]$model,
    rmse_cv    = champions[[tgt]]$rmse_cv
  )
})

message("\n  Champions por horizonte:")
print(champion_table)

# ── Gráfico: baseline vs tuned ────────────────────────────────────────────────

section("Gerando gráfico baseline vs tuned")

if ("rmse_baseline" %in% names(tuning_summary)) {

  plot_data <- tuning_summary |>
    mutate(horizonte_label = factor(
      str_remove(horizonte, "target_"),
      levels = c("5d", "30d", "90d")
    )) |>
    pivot_longer(cols = c(rmse_baseline, rmse_tuned),
                 names_to = "fase", values_to = "rmse") |>
    mutate(fase = recode(fase,
                         rmse_baseline = "Baseline",
                         rmse_tuned    = "Tuned"))

  p_tuning <- plot_data |>
    ggplot(aes(x = modelo, y = rmse, fill = fase)) +
    geom_col(position = position_dodge(width = 0.7), width = 0.6) +
    geom_text(aes(label = sprintf("%.4f", rmse)),
              position = position_dodge(width = 0.7),
              vjust = -0.4, size = 3) +
    facet_wrap(~ horizonte_label, scales = "free_y", ncol = 3) +
    scale_fill_manual(values = c("Baseline" = "#B0C4DE", "Tuned" = "#2E86AB")) +
    labs(
      title    = "Baseline vs Tuned — RMSE walk-forward CV",
      subtitle = "Menor = melhor. Tuned usa melhor configuração do Latin Hypercube (30 iter).",
      x        = NULL, y = "RMSE (retorno log)", fill = NULL
    ) +
    theme_minimal(base_size = 12) +
    theme(strip.text = element_text(face = "bold"),
          legend.position = "top")

  ggsave(
    here("outputs", "figures", "tuning-comparison.png"),
    plot  = p_tuning,
    width = 13, height = 5, dpi = 150
  )
  message("  -> outputs/figures/tuning-comparison.png salvo")
}

# ── Relatório ─────────────────────────────────────────────────────────────────

section("Escrevendo relatório")

summary_lines <- c(
  "══════════════════════════════════════════════════════════",
  "  Hyperparameter Tuning dolaR — Resumo",
  "══════════════════════════════════════════════════════════",
  sprintf("  Train+Val    : %d obs", nrow(train_val)),
  sprintf("  CV strategy  : sliding_window (%d folds)", nrow(wf_folds)),
  "  Grid         : Latin Hypercube, 30 configurações por modelo",
  "",
  "  Melhoria pós-tuning:",
  paste0("  ", capture.output(print(tuning_summary))),
  "",
  "  Champions (melhor modelo tunado por horizonte):",
  paste0("  ", capture.output(print(champion_table))),
  "",
  "  Arquivos gerados:",
  "  - models/tuned/champion-target_*.rds   (fit final em train_val)",
  "  - models/tuned/champion-wf-target_*.rds",
  "  - outputs/tables/tuning-results.csv",
  "  - outputs/figures/tuning-comparison.png",
  "",
  "  ARIMA D+5 benchmark: 0.01570 (referência)",
  "",
  "  Próximo passo: scripts/13-evaluation.R",
  "══════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "12-tuning-summary.txt"))
writeLines(as.character(Sys.time()),
           here("checkpoints", "07-tuning.complete"))

message("\n  Fase 7 concluída → models/tuned/")
message("  Próximo: scripts/13-evaluation.R")
