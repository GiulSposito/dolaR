# Ada — Plano: Adicionar Datasets Prioritários e Médios

## Diagnóstico de disponibilidade (testado em 2026-07-02)

### Confirmados disponíveis via API gratuita

| Fonte | Série/Tabela | Variável | Obs | Freq | Prioridade |
|-------|-------------|----------|-----|------|------------|
| BCB SGS 5364 | resultado_primario | resultado primário gov. central | 192 | mensal | Alta |
| BCB SGS 22708 | balanca_comercial | saldo semanal fluxo cambial | 192 | mensal | Alta |
| BCB SGS 4380 | ibc_br | IBC-Br (proxy PIB mensal) | 192 | mensal | Alta/Média |
| BCB SGS 24369 | desemprego_br | taxa desemprego (PNAD) | 166 | mensal | Média |
| BCB SGS 13762 | dbgg_pib | dívida bruta % PIB | 192 | mensal | Alta |
| FRED PIORECRUSDM | minerio_ferro | minério de ferro World Bank | 192 | mensal | Alta (proxy) |
| FRED PSOYBUSDM | soja | soja preço World Bank | 192 | mensal | Alta |
| FRED UMCSENT | consumer_sentiment | confiança consumidor EUA | 192 | mensal | Média |
| FRED T10YIE | breakeven_10y | inflação implícita 10y EUA | 4174 | diária | Alta |
| FRED T5YIE | breakeven_5y | inflação implícita 5y EUA | 4174 | diária | Alta |
| FRED BAMLH0A0HYM2 | us_hy_spread | spread HY EUA (risk-off) | 662 | diária | Média |
| SIDRA 3653 | pim_geral | produção industrial (até 2022) | 241 | mensal | Média |
| SIDRA 5932 | pib_trimestral | PIB trimestral IBGE | 121 | trimestral | Média |
| SIDRA 6381 | desemprego_pnad | desemprego PNAD trimestral | 171 | trimestral | Média |

### Não disponíveis / descartados para MVP

| Variável | Motivo |
|----------|--------|
| Curva ANBIMA (DI futuro, NTN-B) | Token sandbox — 401 nos endpoints de preços; requer conta produção |
| CDS Brasil direto | SGS 28763 = valores em escala errada (~33M); FRED EMBI = anual (11 obs); EWZ permanece como proxy |
| PMC varejo SIDRA | Tabelas testadas retornam erro de URL — investigar em fase posterior |
| PIM pós-2022 SIDRA | Tabela 3653 vai até 202201; tabelas mais recentes não respondem na sidrar atual |
| Comex Stat | API retorna 403 Forbidden |
| ANBIMA curva | 401 Unauthorized — credencial sandbox |

---

## Arquitetura de implementação

### Script novo: `07-collect-fiscal-activity.R`

Coleta em um único script as séries de **atividade econômica BR** e **fiscal**:
- BCB SGS: resultado_primario, balanca_comercial, ibc_br, desemprego_br, dbgg_pib
- SIDRA: PIM 3653 (mensal até 2022), PIB 5932 (trimestral), PNAD 6381 (trimestral)
- Output: `data/raw/bcb_sgs_fiscal/bcb_sgs_fiscal.csv` + `data/raw/ibge/activity_sidra.csv`

### Script novo: `08-collect-global-indicators.R`

Coleta **FRED adicional** (séries não coletadas no 04):
- minerio_ferro (PIORECRUSDM), soja (PSOYBUSDM), consumer_sentiment (UMCSENT)
- breakeven_10y (T10YIE), breakeven_5y (T5YIE)
- us_hy_spread (BAMLH0A0HYM2)
- Output: `data/raw/fred/fred_additional.csv`

### Atualizar `06-build-dataset.R`

Adicionar em `load_raw_data()` e `build_daily_dataset()`:
- `raw$sgs_fiscal` — join mensal com forward-fill
- `raw$activity_sidra` — join mensal/trimestral com forward-fill
- `raw$fred_add` — join diário (breakevens, HY spread) + mensal forward-fill (minerio, soja, sentiment)

### Renumeração dos scripts

Script atual `06-build-dataset.R` → renomear para `09-build-dataset.R` (ou manter 06 e referenciar como última etapa). Opção mais simples: **manter a numeração atual** e inserir os novos como 07 e 08 — o build já é `06-build-dataset.R` e será re-executado no final de qualquer forma.

---

## Colunas que serão adicionadas ao dataset

| Coluna | Fonte | Freq | Forward-fill |
|--------|-------|------|-------------|
| `resultado_primario` | SGS 5364 | mensal | sim |
| `balanca_comercial_bcb` | SGS 22708 | mensal | sim |
| `ibc_br` | SGS 4380 | mensal | sim |
| `desemprego_br` | SGS 24369 | mensal | sim |
| `dbgg_pib` | SGS 13762 | mensal | sim |
| `pim_geral` | SIDRA 3653 | mensal | sim |
| `pib_trimestral` | SIDRA 5932 | trimestral | sim |
| `desemprego_pnad` | SIDRA 6381 | trimestral | sim |
| `minerio_ferro` | FRED PIORECRUSDM | mensal | sim |
| `soja` | FRED PSOYBUSDM | mensal | sim |
| `consumer_sentiment_us` | FRED UMCSENT | mensal | sim |
| `breakeven_10y` | FRED T10YIE | diária | não |
| `breakeven_5y` | FRED T5YIE | diária | não |
| `us_hy_spread` | FRED BAMLH0A0HYM2 | diária | não |

**Total: +14 colunas → dataset passa de 46 para ~60 colunas.**

---

## Sequência de execução

1. Criar `scripts/07-collect-fiscal-activity.R`
2. Criar `scripts/08-collect-global-indicators.R`
3. Atualizar `scripts/06-build-dataset.R` (add load + join das novas fontes)
4. Executar script 07 via Rscript
5. Executar script 08 via Rscript
6. Re-executar script 06 para rebuild do dataset
7. Verificar colunas e checkpoint
8. Atualizar memory files
