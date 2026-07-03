# Phase 1 — Setup & Verification
# Owner: Ada
# Purpose: Verify project structure, configure R session, install core packages.

library(here)

# ── Opções globais ────────────────────────────────────────────────────────────
options(
  scipen = 999,         # evita notação científica em outputs
  encoding = "UTF-8",
  warn = 1              # warnings imediatos
)

# ── Verificação da estrutura de diretórios ────────────────────────────────────
required_dirs <- c(
  "R/collect", "R/features", "R/utils",
  "scripts",
  "data/raw", "data/processed", "data/reference",
  "models", "outputs/figures", "outputs/tables",
  "reports", "checkpoints", "logs"
)

missing_dirs <- required_dirs[!dir.exists(here(required_dirs))]
if (length(missing_dirs) > 0) {
  stop("Diretórios faltando: ", paste(missing_dirs, collapse = ", "),
       "\nRode: source(here('scripts/01-setup.R')) após criar a estrutura.")
}
cat("OK Estrutura de diretórios verificada.\n")

# ── Verificação de pacotes essenciais ─────────────────────────────────────────
core_pkgs <- c(
  "tidyverse", "lubridate", "here", "conflicted",
  "skimr", "janitor", "naniar",
  "rbcb", "tidyquant", "fredr", "sidrar",
  "tidymodels", "timetk",
  "patchwork", "scales", "gt"
)

missing_pkgs <- core_pkgs[!sapply(core_pkgs, requireNamespace, quietly = TRUE)]
if (length(missing_pkgs) > 0) {
  cat("\nPacotes não instalados:\n")
  cat(paste(" -", missing_pkgs, collapse = "\n"), "\n\n")
  cat("Para instalar, rode:\n")
  cat('install.packages(c(', paste0('"', missing_pkgs, '"', collapse = ", "), "))\n\n")
  cat("Depois: renv::snapshot() para registrar no renv.lock\n")
} else {
  cat("OK Todos os pacotes essenciais encontrados.\n")
}

# ── Resolução de conflitos entre pacotes ──────────────────────────────────────
if (requireNamespace("conflicted", quietly = TRUE)) {
  library(conflicted)
  conflict_prefer("filter", "dplyr")
  conflict_prefer("select", "dplyr")
  conflict_prefer("lag",    "dplyr")
}

# ── Verificação de chaves de API ──────────────────────────────────────────────
cat("\nVerificação de variáveis de ambiente:\n")
api_vars <- c("FRED_API_KEY")
for (v in api_vars) {
  val <- Sys.getenv(v)
  status <- if (nchar(val) > 0) "OK (configurado)" else "FALTANDO"
  cat(sprintf("  %s: %s\n", v, status))
}
cat("  (configurar em .Renviron.local ou ~/.Renviron)\n\n")

# ── Checkpoint ────────────────────────────────────────────────────────────────
writeLines(as.character(Sys.time()), here("checkpoints", "01-setup.complete"))
cat("Fase 1 concluída. Próximo: scripts/02-collect-market.R\n")
