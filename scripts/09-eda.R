# Fase 4 — Exploratory Data Analysis (EDA)
# Owner: Grace
# Input:  data/processed/daily_dataset.rds   — dataset completo (com targets futuros)
#         data/processed/model_dataset.rds   — dataset sem leakage (para análise de features)
# Output: outputs/figures/eda-*.png
#         outputs/tables/eda-*.csv
#         reports/09-eda-summary.txt
#
# Nota: usa daily_dataset para visualizar a série completa do target,
#       mas model_dataset para análise de features (evita olhar para o futuro).

library(tidyverse)
library(lubridate)
library(here)
library(skimr)
library(naniar)
library(corrplot)
library(patchwork)
library(scales)
library(slider)  # rolling functions

# Garantir diretórios de output
dir.create(here("outputs", "figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(here("outputs", "tables"),  recursive = TRUE, showWarnings = FALSE)
dir.create(here("reports"),            recursive = TRUE, showWarnings = FALSE)
dir.create(here("checkpoints"),        recursive = TRUE, showWarnings = FALSE)

# ── Helpers ───────────────────────────────────────────────────────────────────

save_plot <- function(p, name, w = 12, h = 7, dpi = 200) {
  path <- here("outputs", "figures", paste0("eda-", name, ".png"))
  ggsave(path, p, width = w, height = h, dpi = dpi, bg = "white")
  message(sprintf("  -> %s", basename(path)))
  invisible(path)
}

section <- function(title) {
  message(sprintf("\n══ %s ══", title))
}

# ── Carregar dados ─────────────────────────────────────────────────────────────

section("Carregando dados")
ds_full  <- readRDS(here("data", "processed", "daily_dataset.rds"))
ds_model <- readRDS(here("data", "processed", "model_dataset.rds"))

message(sprintf("  daily_dataset : %d obs x %d vars  (%s a %s)",
                nrow(ds_full), ncol(ds_full),
                min(ds_full$date), max(ds_full$date)))
message(sprintf("  model_dataset : %d obs x %d vars  (%s a %s)",
                nrow(ds_model), ncol(ds_model),
                min(ds_model$date), max(ds_model$date)))

# ══════════════════════════════════════════════════════════════════════════════
# Seção 1 — Visão geral do dataset
# ══════════════════════════════════════════════════════════════════════════════

section("Visão geral — skimr")

skim_result <- skim(ds_model)
print(skim_result)

# Salvar skim como CSV
skim_df <- as.data.frame(skim_result)
write_csv(skim_df, here("outputs", "tables", "eda-skim-summary.csv"))

# ══════════════════════════════════════════════════════════════════════════════
# Seção 2 — Série temporal do USD/BRL e targets
# ══════════════════════════════════════════════════════════════════════════════

section("Série temporal USD/BRL")

# 2a. USD/BRL PTAX ao longo do tempo
p_ptax <- ds_full |>
  ggplot(aes(x = date, y = usd_brl_ptax)) +
  geom_line(color = "#2c7bb6", linewidth = 0.5) +
  geom_smooth(method = "loess", span = 0.15, se = FALSE,
              color = "#d7191c", linewidth = 1) +
  scale_y_continuous(labels = dollar_format(prefix = "R$")) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(title = "USD/BRL PTAX — 2010 a 2026",
       subtitle = "Linha vermelha: tendência LOESS",
       x = NULL, y = "BRL / USD") +
  theme_minimal(base_size = 12)

save_plot(p_ptax, "01-usd-brl-ptax")

# 2b. Retornos diários (log)
ds_model_ret <- ds_model |>
  arrange(date) |>
  mutate(ret_1d = log(usd_brl_ptax / lag(usd_brl_ptax)))

p_ret <- ds_model_ret |>
  ggplot(aes(x = date, y = ret_1d)) +
  geom_col(aes(fill = ret_1d > 0), width = 1) +
  scale_fill_manual(values = c("TRUE" = "#d7191c", "FALSE" = "#2c7bb6"),
                    labels = c("TRUE" = "Alta", "FALSE" = "Queda"),
                    name = NULL) +
  scale_y_continuous(labels = percent_format(accuracy = 0.1)) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  labs(title = "Retorno diário logarítmico do USD/BRL",
       x = NULL, y = "Retorno log (1 dia)") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

save_plot(p_ret, "02-retornos-diarios")

# ══════════════════════════════════════════════════════════════════════════════
# Seção 3 — Distribuição dos targets (D+5, D+30, D+90)
# ══════════════════════════════════════════════════════════════════════════════

section("Distribuição dos targets")

targets_long <- ds_model |>
  select(date, target_5d, target_30d, target_90d) |>
  pivot_longer(-date, names_to = "horizonte", values_to = "retorno") |>
  mutate(horizonte = factor(horizonte,
                            levels = c("target_5d", "target_30d", "target_90d"),
                            labels = c("D+5", "D+30", "D+90")))

# Estatísticas resumidas por horizonte
target_stats <- targets_long |>
  group_by(horizonte) |>
  summarise(
    n       = n(),
    media   = mean(retorno, na.rm = TRUE),
    dp      = sd(retorno, na.rm = TRUE),
    min     = min(retorno, na.rm = TRUE),
    p25     = quantile(retorno, 0.25, na.rm = TRUE),
    mediana = median(retorno, na.rm = TRUE),
    p75     = quantile(retorno, 0.75, na.rm = TRUE),
    max     = max(retorno, na.rm = TRUE),
    skew    = (mean(retorno, na.rm = TRUE) - median(retorno, na.rm = TRUE)) / sd(retorno, na.rm = TRUE),
    pct_alta = mean(retorno > 0, na.rm = TRUE)
  )
print(target_stats)
write_csv(target_stats, here("outputs", "tables", "eda-target-stats.csv"))

# Histogramas com curva normal sobreposta
p_hist_targets <- targets_long |>
  ggplot(aes(x = retorno)) +
  geom_histogram(aes(y = after_stat(density)), bins = 60,
                 fill = "#4575b4", alpha = 0.7, color = "white", linewidth = 0.2) +
  stat_function(fun = dnorm,
                args = list(mean = 0,
                            sd = sd(ds_model$target_30d, na.rm = TRUE)),
                color = "#d7191c", linewidth = 1, linetype = "dashed") +
  geom_vline(xintercept = 0, color = "black", linewidth = 0.7) +
  facet_wrap(~horizonte, ncol = 1, scales = "free") +
  scale_x_continuous(labels = percent_format(accuracy = 1)) +
  labs(title = "Distribuição dos retornos log por horizonte",
       subtitle = "Linha vermelha tracejada: Normal(0, σ_30d) de referência",
       x = "Retorno log", y = "Densidade") +
  theme_minimal(base_size = 12)

save_plot(p_hist_targets, "03-dist-targets", w = 10, h = 10)

# Boxplot comparativo
p_box_targets <- targets_long |>
  ggplot(aes(x = horizonte, y = retorno, fill = horizonte)) +
  geom_boxplot(outlier.size = 0.5, outlier.alpha = 0.3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_fill_brewer(palette = "Set2") +
  labs(title = "Boxplot dos retornos por horizonte de previsão",
       x = "Horizonte", y = "Retorno log") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "none")

save_plot(p_box_targets, "04-boxplot-targets", w = 8, h = 6)

# ══════════════════════════════════════════════════════════════════════════════
# Seção 4 — Qualidade dos dados: missing values
# ══════════════════════════════════════════════════════════════════════════════

section("Missing values")

miss_summary <- miss_var_summary(ds_model)
miss_relevant <- miss_summary |> filter(pct_miss > 0)
print(miss_relevant, n = 30)
write_csv(miss_summary, here("outputs", "tables", "eda-missing-summary.csv"))

if (nrow(miss_relevant) > 0) {
  p_miss <- gg_miss_var(ds_model |> select(-date), show_pct = TRUE) +
    labs(title = "% de valores ausentes por variável (model_dataset)") +
    theme_minimal(base_size = 11)
  save_plot(p_miss, "05-missing-vars", w = 10, h = 10)
} else {
  message("  Nenhuma variável com missing no model_dataset")
}

# Disponibilidade temporal por grupo de variáveis
section("Disponibilidade temporal das séries")

# Verificar quando cada série começa (primeira obs não-NA)
serie_inicio <- ds_model |>
  select(-date, -starts_with("target_"), -starts_with("dir_")) |>
  summarise(across(everything(), ~ min(ds_model$date[!is.na(.x)]))) |>
  pivot_longer(everything(), names_to = "variavel", values_to = "inicio") |>
  arrange(inicio)

write_csv(serie_inicio, here("outputs", "tables", "eda-serie-inicio.csv"))

# Mostrar séries que começam depois de 2012
series_tardias <- serie_inicio |> filter(inicio > as.Date("2012-01-01"))
if (nrow(series_tardias) > 0) {
  message("  Séries com início tardio (> 2012-01-01):")
  print(series_tardias)
}

# ══════════════════════════════════════════════════════════════════════════════
# Seção 5 — Correlação com targets
# ══════════════════════════════════════════════════════════════════════════════

section("Correlação features vs targets")

# Variáveis numéricas (excluindo date e direction targets)
numeric_vars <- ds_model |>
  select(-date, -starts_with("dir_")) |>
  select(where(is.numeric)) |>
  names()

# Correlação de cada feature com cada target
cor_with_targets <- map_dfr(c("target_5d", "target_30d", "target_90d"), function(tgt) {
  features <- setdiff(numeric_vars, c("target_5d", "target_30d", "target_90d",
                                      "usd_brl_ptax"))
  map_dfr(features, function(feat) {
    df_pair <- ds_model |>
      select(all_of(c(feat, tgt))) |>
      drop_na()
    if (nrow(df_pair) < 100) return(NULL)
    cor_val <- cor(df_pair[[feat]], df_pair[[tgt]], use = "complete.obs")
    tibble(feature = feat, target = tgt, cor = cor_val, n = nrow(df_pair))
  })
})

# Top correlações (abs > 0.10) por target
top_cor <- cor_with_targets |>
  filter(abs(cor) > 0.05) |>
  arrange(target, desc(abs(cor)))

write_csv(cor_with_targets, here("outputs", "tables", "eda-correlacoes-targets.csv"))
write_csv(top_cor, here("outputs", "tables", "eda-top-correlacoes.csv"))

message("  Top correlações com target_30d:")
top_cor |> filter(target == "target_30d") |> slice_head(n = 15) |> print()

# Gráfico de barras: top 20 correlações com target_30d
top20_30d <- cor_with_targets |>
  filter(target == "target_30d") |>
  slice_max(abs(cor), n = 20)

p_cor_bar <- top20_30d |>
  mutate(feature = fct_reorder(feature, cor)) |>
  ggplot(aes(x = cor, y = feature, fill = cor > 0)) +
  geom_col() +
  geom_vline(xintercept = 0, color = "black", linewidth = 0.5) +
  scale_fill_manual(values = c("TRUE" = "#d7191c", "FALSE" = "#2c7bb6"),
                    guide = "none") +
  scale_x_continuous(labels = number_format(accuracy = 0.01)) +
  labs(title = "Top 20 correlações com target_30d",
       subtitle = "Correlação de Pearson | features vs retorno log D+30",
       x = "Correlação", y = NULL) +
  theme_minimal(base_size = 12)

save_plot(p_cor_bar, "06-cor-features-target30d", w = 10, h = 8)

# ══════════════════════════════════════════════════════════════════════════════
# Seção 6 — Matriz de correlação das variáveis de mercado
# ══════════════════════════════════════════════════════════════════════════════

section("Matriz de correlação — mercado")

mercado_vars <- c(
  "usd_brl_ptax", "dxy", "vix", "ewz", "ibovespa", "sp500", "nasdaq",
  "petroleo_brent", "petroleo_wti", "ouro", "cobre",
  "treasury_2y", "treasury_10y", "sofr", "cdi_diario",
  "breakeven_10y", "us_hy_spread"
)
mercado_vars <- intersect(mercado_vars, names(ds_model))

cor_mercado <- ds_model |>
  select(all_of(mercado_vars)) |>
  drop_na() |>
  cor()

png(here("outputs", "figures", "eda-07-corrplot-mercado.png"),
    width = 12, height = 12, units = "in", res = 200, bg = "white")
corrplot(cor_mercado,
         method    = "color",
         type      = "upper",
         order     = "hclust",
         tl.col    = "black",
         tl.srt    = 45,
         tl.cex    = 0.8,
         addCoef.col = "black",
         number.cex  = 0.6,
         col         = colorRampPalette(c("#2166ac", "white", "#d73027"))(200),
         title       = "Correlação — variáveis de mercado",
         mar         = c(0, 0, 1, 0))
dev.off()
message("  -> eda-07-corrplot-mercado.png")

# Identificar pares de alta correlação (|r| > 0.85) — candidatos a redundância
high_cor_pairs <- cor_mercado |>
  as.data.frame() |>
  rownames_to_column("var1") |>
  pivot_longer(-var1, names_to = "var2", values_to = "cor") |>
  filter(var1 < var2, abs(cor) > 0.85) |>
  arrange(desc(abs(cor)))

if (nrow(high_cor_pairs) > 0) {
  message("  Pares com |cor| > 0.85 (candidatos à remoção):")
  print(high_cor_pairs)
  write_csv(high_cor_pairs, here("outputs", "tables", "eda-alta-correlacao.csv"))
}

# ══════════════════════════════════════════════════════════════════════════════
# Seção 7 — Volatilidade e regime do USD/BRL
# ══════════════════════════════════════════════════════════════════════════════

section("Volatilidade do USD/BRL")

ds_vol <- ds_model |>
  arrange(date) |>
  mutate(
    ret_1d = log(usd_brl_ptax / lag(usd_brl_ptax)),
    vol_20d = slider::slide_dbl(ret_1d, sd, .before = 19, .complete = TRUE) * sqrt(252),
    vol_60d = slider::slide_dbl(ret_1d, sd, .before = 59, .complete = TRUE) * sqrt(252)
  )

p_vol <- ds_vol |>
  select(date, vol_20d, vol_60d) |>
  pivot_longer(-date, names_to = "janela", values_to = "vol") |>
  mutate(janela = recode(janela, "vol_20d" = "20 dias", "vol_60d" = "60 dias")) |>
  ggplot(aes(x = date, y = vol, color = janela)) +
  geom_line(alpha = 0.8) +
  scale_y_continuous(labels = percent_format(accuracy = 1)) +
  scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
  scale_color_manual(values = c("20 dias" = "#4575b4", "60 dias" = "#d73027")) +
  labs(title = "Volatilidade anualizada do USD/BRL (rolling)",
       x = NULL, y = "Volatilidade anualizada", color = "Janela") +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")

save_plot(p_vol, "08-volatilidade-usdbrl")

# ══════════════════════════════════════════════════════════════════════════════
# Seção 8 — Focus: expectativas de mercado vs realizado
# ══════════════════════════════════════════════════════════════════════════════

section("Focus cambio vs realizado")

focus_vars <- intersect(c("focus_cambio", "focus_selic", "focus_ipca", "focus_pib_total"),
                        names(ds_model))

if ("focus_cambio" %in% focus_vars) {
  p_focus <- ds_model |>
    select(date, usd_brl_ptax, focus_cambio) |>
    drop_na() |>
    ggplot(aes(x = date)) +
    geom_line(aes(y = usd_brl_ptax, color = "PTAX realizado"), linewidth = 0.6) +
    geom_line(aes(y = focus_cambio, color = "Focus: expectativa"), linewidth = 0.6,
              linetype = "dashed") +
    scale_color_manual(values = c("PTAX realizado" = "#2c7bb6",
                                  "Focus: expectativa" = "#d7191c")) +
    scale_y_continuous(labels = dollar_format(prefix = "R$")) +
    scale_x_date(date_breaks = "2 years", date_labels = "%Y") +
    labs(title = "PTAX realizado vs Focus (expectativa de câmbio)",
         x = NULL, y = "BRL / USD", color = NULL) +
    theme_minimal(base_size = 12) +
    theme(legend.position = "bottom")

  save_plot(p_focus, "09-focus-vs-ptax")

  # Scatter focus_cambio vs target_30d
  p_scatter_focus <- ds_model |>
    select(date, focus_cambio, usd_brl_ptax, target_30d) |>
    drop_na() |>
    mutate(erro_focus = log(focus_cambio / usd_brl_ptax)) |>
    ggplot(aes(x = erro_focus, y = target_30d)) +
    geom_point(alpha = 0.15, size = 0.8, color = "#4575b4") +
    geom_smooth(method = "lm", color = "#d7191c", se = TRUE) +
    geom_vline(xintercept = 0, linetype = "dashed", color = "gray50") +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    scale_x_continuous(labels = percent_format(accuracy = 1)) +
    scale_y_continuous(labels = percent_format(accuracy = 1)) +
    labs(title = "Erro do Focus (câmbio esperado - atual) vs Retorno D+30",
         subtitle = "Hipótese: mercado já incorpora a maior parte do movimento",
         x = "log(focus_cambio / usd_brl_ptax)",
         y = "Retorno log D+30") +
    theme_minimal(base_size = 12)

  save_plot(p_scatter_focus, "10-focus-vs-target30d", w = 8, h = 6)
}

# ══════════════════════════════════════════════════════════════════════════════
# Seção 9 — Autocorrelação dos targets
# ══════════════════════════════════════════════════════════════════════════════

section("Autocorrelação dos targets")

# ACF para cada horizonte
acf_plot <- function(serie, titulo, lags = 40) {
  acf_obj <- acf(serie[!is.na(serie)], lag.max = lags, plot = FALSE)
  ci <- qnorm(0.975) / sqrt(length(serie))

  tibble(
    lag = acf_obj$lag[-1],
    acf = acf_obj$acf[-1]
  ) |>
    ggplot(aes(x = lag, y = acf)) +
    geom_col(aes(fill = abs(acf) > ci), width = 0.8) +
    geom_hline(yintercept = c(-ci, ci), linetype = "dashed", color = "red") +
    geom_hline(yintercept = 0, color = "black") +
    scale_fill_manual(values = c("TRUE" = "#d7191c", "FALSE" = "#4575b4"),
                      guide = "none") +
    labs(title = titulo, x = "Lag (dias)", y = "ACF") +
    theme_minimal(base_size = 11)
}

p_acf_5  <- acf_plot(ds_model$target_5d,  "ACF — target_5d  (D+5)")
p_acf_30 <- acf_plot(ds_model$target_30d, "ACF — target_30d (D+30)")
p_acf_90 <- acf_plot(ds_model$target_90d, "ACF — target_90d (D+90)")

p_acf_all <- p_acf_5 / p_acf_30 / p_acf_90 +
  plot_annotation(title = "Autocorrelação dos retornos log por horizonte",
                  subtitle = "Barras vermelhas: significativas a 5% | Linhas vermelhas: IC 95%")

save_plot(p_acf_all, "11-acf-targets", w = 12, h = 10)

# ══════════════════════════════════════════════════════════════════════════════
# Seção 10 — Variáveis com maior % de missing — análise de impacto
# ══════════════════════════════════════════════════════════════════════════════

section("Análise de séries problemáticas")

# Verificar séries conhecidas como problemáticas
problematicas <- c("saldo_cambial", "us_hy_spread", "pim_geral", "sofr")
problematicas_existentes <- intersect(problematicas, names(ds_model))

if (length(problematicas_existentes) > 0) {
  prob_summary <- map_dfr(problematicas_existentes, function(v) {
    vals <- ds_model[[v]]
    tibble(
      variavel = v,
      n_obs    = sum(!is.na(vals)),
      pct_miss = mean(is.na(vals)),
      inicio   = if (any(!is.na(vals))) min(ds_model$date[!is.na(vals)]) else as.Date(NA)
    )
  })
  message("  Séries problemáticas:")
  print(prob_summary, n = 20)
  write_csv(prob_summary, here("outputs", "tables", "eda-series-problematicas.csv"))
}

# ══════════════════════════════════════════════════════════════════════════════
# Seção 11 — Resumo final e recomendações
# ══════════════════════════════════════════════════════════════════════════════

section("Resumo e recomendações")

n_missing_vars <- miss_summary |> filter(pct_miss > 0.10) |> nrow()
n_high_cor     <- if (exists("high_cor_pairs")) nrow(high_cor_pairs) else 0

summary_lines <- c(
  "══════════════════════════════════════════════════════════",
  "  EDA dolaR — Resumo",
  "══════════════════════════════════════════════════════════",
  sprintf("  Dataset: %d obs x %d vars (%s a %s)",
          nrow(ds_model), ncol(ds_model),
          min(ds_model$date), max(ds_model$date)),
  sprintf("  Variáveis com >10%% missing: %d", n_missing_vars),
  sprintf("  Pares com alta correlação (>0.85): %d", n_high_cor),
  "",
  "  Recomendações:",
  "  1. Considerar remover saldo_cambial (<14 obs úteis)",
  "  2. us_hy_spread: usar com cautela (só desde 2023-07)",
  "  3. pim_geral: dado desatualizado — forward-fill cresce artificialmente",
  "  4. sofr: lag fill pré-2018 pode criar leakage sutil",
  "  5. Próximo passo: 10-feature-engineering.R",
  "══════════════════════════════════════════════════════════"
)

writeLines(summary_lines)
writeLines(summary_lines, here("reports", "09-eda-summary.txt"))
writeLines(as.character(Sys.time()), here("checkpoints", "04-eda.complete"))

message("\n  Fase 4 concluída. Plots em outputs/figures/eda-*.png")
message("  Próximo: scripts/10-feature-engineering.R")
