# Fase 6 — Baseline Modeling
# Owner: Alan
# Input:  data/processed/features_dataset.rds
# Output: models/baseline/          — workflow objects por horizonte + modelo
#         outputs/tables/baseline-cv-results.csv
#         outputs/figures/baseline-comparison.png
#         reports/11-baseline-summary.txt
#
# Estratégia:
#   - 3 modelos independentes: D+5, D+30, D+90
#   - Validação walk-forward (sliding_window) — nunca split aleatório
#   - 5 modelos: Null, Ridge, ElasticNet, RandomForest, XGBoost
#   - Métricas primárias: RMSE e MAE (retornos log são simétricos → RMSE ok)
#   - Test set (últimos 20%) NUNCA tocado aqui — somente em 12-evaluation.R
#
# Princípio: BREADTH BEFORE DEPTH — defaults razoáveis, sem tuning ainda.
#            Todos os modelos treinam nas mesmas janelas de CV.

library(tidyverse)
library(lubridate)
library(here)
library(tidymodels)
library(slider)

# Paralelo via future (doFuture/doParallel não instalados)
library(future)
plan(multisession, workers = max(1L, parallel::detectCores() - 1L))
options(future.globals.maxSize = 2 * 1024^3)  # 2 GB

section <- function(title) message(sprintf("\n══ %s ══", title))

dir.create(here("models", "baseline"),      recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "tables"),       recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "figures"),      recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),                 recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),             recursive = TRUE, showWarnings = FALSE)

# ── Carregar features_dataset ─────────────────────────────────────────────────

section("Carregando features_dataset")
ds <- readRDS(here("data", "processed", "features_dataset.rds")) |>
  arrange(date)

message(sprintf("  %d obs × %d vars  (%s a %s)",
                nrow(ds), ncol(ds), min(ds$date), max(ds$date)))

# Verificar se targets existem
targets <- c("target_5d", "target_30d", "target_90d")
stopifnot("Targets ausentes no dataset" = all(targets %in% names(ds)))

# ── Features a usar como preditores ──────────────────────────────────────────
#
# Excluir: date, targets de todos os horizontes, direções (dir_*),
# séries brutas de preço (usd_brl_ptax, usd_brl) — já representadas via retornos,
# e colunas de id se existirem.
#
# Manter: todas as features G1-G5 + variáveis macro brutas (selic_meta,
#   ipca_acum12m, fed_funds, etc.) que entram diretamente no modelo.

colunas_excluir <- c(
  "date",
  targets,
  grep("^dir_", names(ds), value = TRUE),
  # Preços brutos (informação capturada pelos retornos)
  "usd_brl_ptax", "usd_brl",
  # Séries com cobertura < 50% — excluídas do baseline
  # (us_hy_spread: só desde 2023-07 → ~12% do dataset)
  "us_hy_spread"
)
colunas_excluir <- intersect(colunas_excluir, names(ds))

predictors_all <- setdiff(names(ds), colunas_excluir)
message(sprintf("  Preditores candidatos: %d", length(predictors_all)))

# ── Split temporal: 80% train+val / 20% test (NUNCA tocar test aqui) ─────────

section("Split temporal 80/20")

n_total  <- nrow(ds)
n_test   <- floor(n_total * 0.20)
n_train  <- n_total - n_test
cutoff   <- ds$date[n_train]

train_val <- ds |> filter(date <= cutoff)
test_data  <- ds |> filter(date >  cutoff)

message(sprintf("  Train+Val: %d obs  (%s a %s)", nrow(train_val),
                min(train_val$date), max(train_val$date)))
message(sprintf("  Test      : %d obs  (%s a %s)", nrow(test_data),
                min(test_data$date), max(test_data$date)))
message(sprintf("  Corte     : %s", cutoff))
message("  [AVISO] Test set guardado — será usado SOMENTE em 12-evaluation.R")

saveRDS(test_data, here("models", "test_data.rds"))

# ── Walk-forward CV ────────────────────────────────────────────────────────────
#
# sliding_window (janela rolante fixa):
#   - lookback: 756 dias úteis (~3 anos) — janela de treino
#   - step: 63 dias (~1 trimestre) — avançamento da janela
#   - assess: 63 dias — janela de avaliação (assessment)
#   Resultado: ~30-40 folds cobrindo todo o período de treino.
#
# Por que sliding (janela fixa) em vez de expanding?
#   Câmbio tem regime-breaks (ex: 2015, 2020, Covid). Janela fixa
#   reduz o peso de dados muito antigos que podem distorcer o modelo.

section("Walk-forward CV (sliding_window)")

wf_folds <- rsample::sliding_window(
  train_val,
  lookback  = 756L,   # ~3 anos de treino por fold
  step      = 63L,    # avança ~1 trimestre por vez
  assess_start = 1L,
  assess_stop  = 63L  # avalia ~1 trimestre à frente
)

message(sprintf("  Folds gerados: %d", nrow(wf_folds)))
message(sprintf("  Treino por fold: ~%d obs", 756))
message(sprintf("  Avaliação por fold: ~%d obs", 63))

# ── Métricas ──────────────────────────────────────────────────────────────────

cv_metrics <- yardstick::metric_set(
  yardstick::rmse,
  yardstick::mae,
  yardstick::rsq
)

# ── Helpers ───────────────────────────────────────────────────────────────────

make_recipe <- function(target, data) {
  # Todas as variáveis brutas contínuas podem ter NAs parciais (sofr, pim_geral, etc.)
  # Imputar pela mediana DENTRO do recipe → evita leakage.
  # Normalizar apenas preditores numéricos (necessário para Ridge/ElasticNet).
  # Categoriais (dia_semana, mes, etc.) → dummy.

  recipe(as.formula(paste(target, "~ .")), data = data) |>
    # Remover preditores com variância zero antes de tudo
    step_zv(all_predictors()) |>
    step_nzv(all_predictors(), freq_cut = 95 / 5) |>
    # Imputação mediana para NAs remanescentes
    step_impute_median(all_numeric_predictors()) |>
    # Calendário já é numérico (1-12, 1-7, etc.) — entra direto, sem dummy
    # Normalização (necessário para modelos lineares e melhora XGBoost)
    step_normalize(all_numeric_predictors())
}

# ── Especificações dos modelos ────────────────────────────────────────────────

# Modelo 0 — Null (random walk: predição = 0, i.e. sem variação)
null_spec <- parsnip::null_model(mode = "regression") |>
  parsnip::set_engine("parsnip")

# Modelo 1 — Ridge (penalty alto, mixture = 0)
ridge_spec <- parsnip::linear_reg(penalty = 0.01, mixture = 0) |>
  parsnip::set_engine("glmnet")

# Modelo 2 — Elastic Net (penalty intermediário, mixture = 0.5)
enet_spec <- parsnip::linear_reg(penalty = 0.01, mixture = 0.5) |>
  parsnip::set_engine("glmnet")

# Modelo 3 — Random Forest (defaults tidymodels — 500 árvores)
rf_spec <- parsnip::rand_forest(trees = 500) |>
  parsnip::set_engine("ranger", importance = "impurity", num.threads = 1L) |>
  parsnip::set_mode("regression")

# Modelo 4 — XGBoost (defaults conservadores)
xgb_spec <- parsnip::boost_tree(trees = 300, learn_rate = 0.05, tree_depth = 4) |>
  parsnip::set_engine("xgboost", nthread = 1L) |>
  parsnip::set_mode("regression")

model_specs <- list(
  null   = null_spec,
  ridge  = ridge_spec,
  enet   = enet_spec,
  rf     = rf_spec,
  xgb    = xgb_spec
)

# ── Loop por horizonte ────────────────────────────────────────────────────────

all_results <- list()

for (target in targets) {

  section(sprintf("Horizonte: %s", target))

  # Dataset apenas com este target e os preditores
  data_h <- train_val |> select(all_of(predictors_all), all_of(target))

  # Recipe
  rec <- make_recipe(target, data_h)

  # Workflow set: empacota recipe + cada modelo
  wf_set <- workflow_set(
    preproc = list(rec = rec),
    models  = model_specs
  )

  message(sprintf("  Rodando %d modelos × %d folds (paralelo)...",
                  length(model_specs), nrow(wf_folds)))

  tstart <- proc.time()

  results <- wf_set |>
    workflow_map(
      fn        = "fit_resamples",
      resamples = wf_folds,
      metrics   = cv_metrics,
      control   = tune::control_resamples(
        save_pred     = TRUE,
        save_workflow = TRUE,
        verbose       = FALSE,
        allow_par     = TRUE
      ),
      verbose = TRUE
    )

  elapsed <- round((proc.time() - tstart)[["elapsed"]], 1)
  message(sprintf("  Concluído em %.1fs", elapsed))

  # Guardar resultados deste horizonte
  all_results[[target]] <- results

  # Mostrar ranking rápido
  metrics_h <- collect_metrics(results)
  ranking <- metrics_h |>
    filter(.metric == "rmse") |>
    arrange(mean) |>
    select(wflow_id, mean, std_err)

  message(sprintf("\n  Ranking RMSE — %s:", target))
  print(ranking)

  # Salvar workflow set deste horizonte
  saveRDS(results,
          here("models", "baseline", sprintf("wfset-%s.rds", target)))
}

plan(sequential)  # fechar workers paralelos

# ── Consolidar métricas ───────────────────────────────────────────────────────

section("Consolidando métricas")

cv_results_all <- map_dfr(names(all_results), function(tgt) {
  collect_metrics(all_results[[tgt]]) |>
    mutate(horizonte = tgt, .before = 1)
})

write_csv(cv_results_all,
          here("outputs", "tables", "baseline-cv-results.csv"))

message("  -> outputs/tables/baseline-cv-results.csv salvo")

# Tabela resumo: RMSE por modelo × horizonte
rmse_summary <- cv_results_all |>
  filter(.metric == "rmse") |>
  select(horizonte, wflow_id, rmse_mean = mean, rmse_se = std_err) |>
  mutate(
    horizonte = str_remove(horizonte, "target_"),
    wflow_id  = str_remove(wflow_id,  "rec_")
  ) |>
  arrange(horizonte, rmse_mean)

message("\n  Resumo RMSE (CV walk-forward):")
print(rmse_summary |> pivot_wider(names_from = horizonte,
                                  values_from = c(rmse_mean, rmse_se),
                                  names_glue = "{horizonte}_{.value}"))

# ── Gráfico de comparação ─────────────────────────────────────────────────────

section("Gerando gráfico de comparação")

p_compare <- cv_results_all |>
  filter(.metric == "rmse") |>
  mutate(
    modelo    = str_remove(wflow_id, "rec_"),
    horizonte = factor(str_remove(horizonte, "target_"),
                       levels = c("5d", "30d", "90d"))
  ) |>
  ggplot(aes(x = reorder(modelo, mean), y = mean, color = horizonte)) +
  geom_point(size = 3, position = position_dodge(width = 0.4)) +
  geom_errorbar(
    aes(ymin = mean - std_err, ymax = mean + std_err),
    width = 0.2,
    position = position_dodge(width = 0.4)
  ) +
  coord_flip() +
  facet_wrap(~ horizonte, scales = "free_x", ncol = 3) +
  labs(
    title    = "Comparação de modelos baseline — dolaR",
    subtitle = "RMSE walk-forward CV (média ± 1 SE). Menor = melhor.",
    x        = NULL,
    y        = "RMSE (retorno log)",
    caption  = "Modelos com defaults razoáveis — tuning no próximo passo."
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none",
        strip.text = element_text(face = "bold"))

ggsave(
  here("outputs", "figures", "baseline-comparison.png"),
  plot   = p_compare,
  width  = 12, height = 5, dpi = 150
)
message("  -> outputs/figures/baseline-comparison.png salvo")

# ── Seleção dos candidatos para tuning ────────────────────────────────────────

section("Seleção de candidatos para tuning")

# Top 2 por horizonte (excluindo null), garantindo diversidade de família
candidates <- cv_results_all |>
  filter(.metric == "rmse") |>
  mutate(modelo = str_remove(wflow_id, "rec_")) |>
  filter(modelo != "null") |>
  group_by(horizonte) |>
  slice_min(mean, n = 2) |>
  ungroup() |>
  select(horizonte, modelo, rmse_mean = mean)

message("\n  Candidatos selecionados para tuning (Step 3):")
print(candidates)

# Null benchmark para referência
null_benchmark <- cv_results_all |>
  filter(.metric == "rmse", str_detect(wflow_id, "null")) |>
  select(horizonte, null_rmse = mean) |>
  mutate(horizonte_label = str_remove(horizonte, "target_"))

message("\n  Null benchmark (random walk RMSE):")
print(null_benchmark)

# ── Relatório resumo ──────────────────────────────────────────────────────────

section("Escrevendo relatório")

n_folds   <- nrow(wf_folds)
n_models  <- length(model_specs)
n_targets <- length(targets)

summary_lines <- c(
  "══════════════════════════════════════════════════════════",
  "  Baseline Modeling dolaR — Resumo",
  "══════════════════════════════════════════════════════════",
  sprintf("  Dataset train+val : %d obs", nrow(train_val)),
  sprintf("  Dataset test (hold): %d obs  [NÃO TOCADO]", nrow(test_data)),
  sprintf("  CV strategy       : sliding_window (%d folds)", n_folds),
  sprintf("  Modelos testados  : %d (null, ridge, enet, rf, xgb)", n_models),
  sprintf("  Horizontes        : %d (5d, 30d, 90d)", n_targets),
  "",
  "  Null RMSE (random walk baseline):",
  paste0("  ", capture.output(print(null_benchmark))),
  "",
  "  Candidatos para tuning (Top 2 por horizonte):",
  paste0("  ", capture.output(print(candidates))),
  "",
  "  Arquivos gerados:",
  "  - models/baseline/wfset-target_*.rds",
  "  - models/test_data.rds",
  "  - outputs/tables/baseline-cv-results.csv",
  "  - outputs/figures/baseline-comparison.png",
  "",
  "  Próximo passo: scripts/12-tuning.R",
  "══════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "11-baseline-summary.txt"))
writeLines(as.character(Sys.time()), here("checkpoints", "06-baseline-modeling.complete"))

message("\n  Fase 6 concluída → models/baseline/")
message("  Próximo: scripts/12-tuning.R")
