# ============================================================
#  FINAL PROJECT — NVIDIA (NVDA) EMPIRICAL ANALYSIS
#  Course: Financial Econometrics
#  Event:  Q3 FY2024 Earnings Release — November 21, 2023 (after-hours)
#          Market Reaction Date: November 22, 2023 (first trading day)
#  Covers: Returns, EAR/APR, Normality, VaR/ES, CAL, Sharpe,
#          Index Model, CAPM, APT, EMH, Behavioral Finance
# ============================================================

# ---- 0. PACKAGES -------------------------------------------
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  quantmod, PerformanceAnalytics, moments, tseries,
  ggplot2, ggpubr, dplyr, tidyr, scales, lubridate, lmtest
)

# ---- 1. DATA DOWNLOAD --------------------------------------
start_date <- "2020-01-01"
end_date   <- "2024-06-30"

getSymbols("NVDA",  src = "yahoo", from = start_date, to = end_date)
getSymbols("^GSPC", src = "yahoo", from = start_date, to = end_date)
getSymbols("^IRX",  src = "yahoo", from = start_date, to = end_date)  # 13-week T-bill (risk-free)

# Daily log returns
nvda_ret <- na.omit(dailyReturn(Ad(NVDA),  type = "log")); colnames(nvda_ret) <- "NVDA"
gspc_ret <- na.omit(dailyReturn(Ad(GSPC),  type = "log")); colnames(gspc_ret) <- "GSPC"

# Risk-free rate: T-bill annualised → daily
rf_annual <- mean(na.omit(Cl(IRX))) / 100       # e.g. 0.045
rf_daily  <- rf_annual / 252

# Align
common_dates <- intersect(index(nvda_ret), index(gspc_ret))
nvda_ret <- nvda_ret[common_dates]
gspc_ret <- gspc_ret[common_dates]

cat("Data loaded:", nrow(nvda_ret), "trading days\n")
cat("Risk-free rate (annualised):", round(rf_annual * 100, 2), "%\n")

# ============================================================
# SECTION A — RETURNS: LOG vs SIMPLE, EAR vs APR
# ============================================================
cat("\n====== SECTION A: Returns & Compounding ======\n")

# Simple returns
nvda_simple <- na.omit(dailyReturn(Ad(NVDA), type = "arithmetic"))

# Demonstrate log vs simple
cat("Mean daily log return NVDA:    ", round(mean(nvda_ret) * 100, 4), "%\n")
cat("Mean daily simple return NVDA: ", round(mean(nvda_simple) * 100, 4), "%\n")

# EAR vs APR (using the risk-free rate as example)
APR <- rf_annual
n   <- 252   # compounding periods (daily)

EAR_daily    <- (1 + APR/n)^n - 1
EAR_monthly  <- (1 + APR/12)^12 - 1
EAR_annual   <- APR  # continuous ~ APR when quoted as effective

cat(sprintf("\n--- EAR vs APR (Risk-Free Rate = %.2f%% APR) ---\n", APR*100))
cat(sprintf("EAR (daily compounding):   %.4f%%\n", EAR_daily * 100))
cat(sprintf("EAR (monthly compounding): %.4f%%\n", EAR_monthly * 100))
cat(sprintf("APR (stated):              %.4f%%\n", APR * 100))

# Annualise NVDA log return using continuous compounding
nvda_ann_log <- mean(nvda_ret) * 252
cat(sprintf("\nNVDA annualised log return (continuous): %.2f%%\n", nvda_ann_log * 100))

# ============================================================
# SECTION B — DESCRIPTIVE STATISTICS & NORMALITY
# ============================================================
cat("\n====== SECTION B: Descriptive Statistics & Normality ======\n")

desc_stats <- function(x, name) {
  data.frame(
    Asset       = name,
    Mean_Ann    = round(mean(x) * 252, 4),
    StdDev_Ann  = round(sd(x) * sqrt(252), 4),
    Skewness    = round(skewness(x), 4),
    Kurt_Excess = round(kurtosis(x) - 3, 4),
    Min         = round(min(x), 4),
    Max         = round(max(x), 4)
  )
}

stats_table <- rbind(
  desc_stats(as.numeric(nvda_ret), "NVDA"),
  desc_stats(as.numeric(gspc_ret), "S&P 500")
)
print(stats_table)

# Normality tests
# Shapiro-Wilk max n = 5000; sample safely up to however many obs we have
n_obs   <- length(as.numeric(nvda_ret))
sw_size <- min(n_obs, 5000)
set.seed(42)
sw_test <- shapiro.test(sample(as.numeric(nvda_ret), sw_size))
jb_test <- jarque.bera.test(as.numeric(nvda_ret))
cat("\nShapiro-Wilk p-value:", round(sw_test$p.value, 6))
cat("\nJarque-Bera  p-value:", round(jb_test$p.value, 6), "\n")

# Plots
nvda_df <- data.frame(ret = as.numeric(nvda_ret))

p_hist <- ggplot(nvda_df, aes(x = ret)) +
  geom_histogram(aes(y = ..density..), bins = 80, fill = "#76b900", alpha = 0.75, color = "white") +
  stat_function(fun = dnorm, args = list(mean = mean(nvda_df$ret), sd = sd(nvda_df$ret)),
                color = "black", linewidth = 0.9, linetype = "dashed") +
  labs(title = "NVDA Daily Log-Returns: Distribution vs Normal",
       x = "Log-Return", y = "Density") +
  theme_minimal(base_size = 13)

p_qq <- ggplot(nvda_df, aes(sample = ret)) +
  stat_qq(color = "#76b900", alpha = 0.5) +
  stat_qq_line(color = "black", linewidth = 0.8) +
  labs(title = "Q-Q Plot — NVDA Daily Log-Returns",
       x = "Theoretical Quantiles", y = "Sample Quantiles") +
  theme_minimal(base_size = 13)

# ============================================================
# SECTION C — VaR & EXPECTED SHORTFALL
# ============================================================
cat("\n====== SECTION C: VaR & Expected Shortfall ======\n")

conf_levels <- c(0.90, 0.95, 0.99)

# Compute one confidence level at a time to avoid dimnames dimension mismatch
VaR_hist <- sapply(conf_levels, function(p) as.numeric(VaR(nvda_ret, p = p, method = "historical")))
ES_hist  <- sapply(conf_levels, function(p) as.numeric(ES(nvda_ret,  p = p, method = "historical")))
VaR_norm <- sapply(conf_levels, function(p) as.numeric(VaR(nvda_ret, p = p, method = "gaussian")))
ES_norm  <- sapply(conf_levels, function(p) as.numeric(ES(nvda_ret,  p = p, method = "gaussian")))
names(VaR_hist) <- names(ES_hist) <- names(VaR_norm) <- names(ES_norm) <- c("90%", "95%", "99%")

risk_table <- data.frame(
  Confidence = c("90%", "95%", "99%"),
  VaR_Hist   = round(VaR_hist, 4),
  VaR_Norm   = round(VaR_norm, 4),
  ES_Hist    = round(ES_hist,  4),
  ES_Norm    = round(ES_norm,  4)
)
cat("\n--- VaR & ES Summary (daily) ---\n")
print(risk_table)

# ============================================================
# SECTION D — CAPITAL ALLOCATION LINE (CAL) & SHARPE RATIO
# ============================================================
cat("\n====== SECTION D: CAL & Sharpe Ratio ======\n")

nvda_excess <- as.numeric(nvda_ret) - rf_daily
gspc_excess <- as.numeric(gspc_ret) - rf_daily

sharpe_nvda <- mean(nvda_excess) / sd(as.numeric(nvda_ret)) * sqrt(252)
sharpe_gspc <- mean(gspc_excess) / sd(as.numeric(gspc_ret)) * sqrt(252)

cat(sprintf("Sharpe Ratio — NVDA:    %.4f\n", sharpe_nvda))
cat(sprintf("Sharpe Ratio — S&P 500: %.4f\n", sharpe_gspc))

# CAL plot: risk vs return for different allocations (w in NVDA, 1-w in Rf)
w_seq    <- seq(0, 2, by = 0.05)   # allow leverage
mu_nvda  <- mean(nvda_ret) * 252
sd_nvda  <- sd(as.numeric(nvda_ret)) * sqrt(252)

cal_df <- data.frame(
  w      = w_seq,
  ret    = rf_annual + w_seq * (mu_nvda - rf_annual),
  risk   = w_seq * sd_nvda
)

p_cal <- ggplot(cal_df, aes(x = risk, y = ret)) +
  geom_line(color = "#76b900", linewidth = 1.2) +
  geom_point(data = data.frame(risk = 0, ret = rf_annual),
             aes(x = risk, y = ret), color = "steelblue", size = 3) +
  geom_point(data = data.frame(risk = sd_nvda, ret = mu_nvda),
             aes(x = risk, y = ret), color = "#76b900", size = 3) +
  annotate("text", x = 0.02, y = rf_annual, label = "Risk-Free", hjust = 0, size = 3.5) +
  annotate("text", x = sd_nvda + 0.01, y = mu_nvda, label = "NVDA", hjust = 0, size = 3.5) +
  scale_y_continuous(labels = scales::percent) +
  scale_x_continuous(labels = scales::percent) +
  labs(title = "Capital Allocation Line (CAL) — NVDA",
       x = "Portfolio Standard Deviation (annualised)",
       y = "Expected Return (annualised)") +
  theme_minimal(base_size = 13)

# ============================================================
# SECTION E — INDEX MODEL (CAPM / MARKET MODEL)
# ============================================================
cat("\n====== SECTION E: Index Model & CAPM ======\n")

ols_data  <- data.frame(nvda = as.numeric(nvda_ret), mkt = as.numeric(gspc_ret))
model_ols <- lm(nvda ~ mkt, data = ols_data)
cat("--- Market Model OLS ---\n")
print(summary(model_ols))

beta_hat  <- coef(model_ols)[2]
alpha_hat <- coef(model_ols)[1]
R2        <- summary(model_ols)$r.squared

# Treynor ratio
treynor_nvda <- (mu_nvda - rf_annual) / beta_hat
cat(sprintf("\nAlpha (daily): %.5f\nBeta:          %.4f\nR-squared:     %.4f\n", alpha_hat, beta_hat, R2))
cat(sprintf("Treynor Ratio: %.4f\n", treynor_nvda))

# Variance decomposition
total_var <- var(as.numeric(nvda_ret))
sys_var   <- beta_hat^2 * var(as.numeric(gspc_ret))
idio_var  <- total_var - sys_var
cat(sprintf("Systematic:    %.2f%%\nIdiosyncratic: %.2f%%\n",
            100*sys_var/total_var, 100*idio_var/total_var))

# Jensen's Alpha test
cat("\n--- Jensen's Alpha significance ---\n")
print(coeftest(model_ols))

# Security Market Line (SML) — CAPM prediction
p_scatter <- ggplot(ols_data, aes(x = mkt, y = nvda)) +
  geom_point(alpha = 0.3, color = "#76b900") +
  geom_smooth(method = "lm", color = "black", se = TRUE) +
  labs(title = sprintf("NVDA vs S&P 500 — Market Model  (β = %.2f, R² = %.2f)", beta_hat, R2),
       x = "S&P 500 Daily Log-Return", y = "NVDA Daily Log-Return") +
  theme_minimal(base_size = 13)

# ============================================================
# SECTION F — APT (MULTI-FACTOR MODEL)
# ============================================================
cat("\n====== SECTION F: APT — Multi-Factor Extension ======\n")

# We proxy Fama-French style factors:
# Factor 1: Market (S&P 500) — already have
# Factor 2: SMB proxy — use Russell 2000 vs S&P 500 spread
# Factor 3: Momentum proxy — use QQQ (tech) vs SPY spread
# Factor 4: AI/Semiconductor sector — use SOX index or SMH ETF

getSymbols(c("SMH", "QQQ", "IWM"), src = "yahoo", from = start_date, to = end_date)

smh_ret <- na.omit(dailyReturn(Ad(SMH), type = "log")); colnames(smh_ret) <- "SMH"
qqq_ret <- na.omit(dailyReturn(Ad(QQQ), type = "log")); colnames(qqq_ret) <- "QQQ"
iwm_ret <- na.omit(dailyReturn(Ad(IWM), type = "log")); colnames(iwm_ret) <- "IWM"

# Align all
all_dates <- Reduce(intersect, list(index(nvda_ret), index(gspc_ret),
                                    index(smh_ret), index(qqq_ret), index(iwm_ret)))
apt_data <- data.frame(
  nvda = as.numeric(nvda_ret[all_dates]),
  mkt  = as.numeric(gspc_ret[all_dates]),
  semi = as.numeric(smh_ret[all_dates]),    # Semiconductor factor
  tech = as.numeric(qqq_ret[all_dates]),    # Tech/growth factor
  smb  = as.numeric(iwm_ret[all_dates]) - as.numeric(gspc_ret[all_dates])  # Size factor proxy
)

apt_model <- lm(nvda ~ mkt + semi + tech + smb, data = apt_data)
cat("--- APT Multi-Factor Model ---\n")
print(summary(apt_model))

cat(sprintf("\nAPT R-squared:        %.4f\nSingle-factor R²:     %.4f\nImprovement:          +%.4f\n",
            summary(apt_model)$r.squared, R2,
            summary(apt_model)$r.squared - R2))

# ============================================================
# SECTION G — EVENT STUDY (EMH TEST)
# ============================================================
cat("\n====== SECTION G: Event Study — Q3 FY2024 Earnings ======\n")

# IMPORTANT: Earnings released after market close on Nov 21, 2023
# Actual market reaction occurred on Nov 22, 2023 (first trading day)
# Setting t=0 to Nov 22 to align with actual trading reaction date

event_date <- as.Date("2023-11-22")  # Changed from 2023-11-21 to actual trading reaction date
est_start  <- event_date - 261       # Adjusted: 260 days before Nov 22
est_end    <- event_date - 12        # Adjusted: 11 days before Nov 22
evt_start  <- event_date - 11        # Adjusted: 10 days before Nov 22
evt_end    <- event_date + 20        # 20 days after Nov 22

est_idx <- index(nvda_ret) >= est_start & index(nvda_ret) <= est_end
evt_idx <- index(nvda_ret) >= evt_start & index(nvda_ret) <= evt_end

nvda_est <- as.numeric(nvda_ret[est_idx])
gspc_est <- as.numeric(gspc_ret[est_idx])
nvda_evt <- as.numeric(nvda_ret[evt_idx])
gspc_evt <- as.numeric(gspc_ret[evt_idx])
dates_evt <- index(nvda_ret[evt_idx])

# Estimate market model on estimation window
est_model <- lm(nvda_est ~ gspc_est)
a_est <- coef(est_model)[1]
b_est <- coef(est_model)[2]
cat(sprintf("Estimation window model: alpha=%.5f, beta=%.4f\n", a_est, b_est))

# Abnormal returns
expected_ret <- a_est + b_est * gspc_evt
AR  <- nvda_evt - expected_ret
CAR <- cumsum(AR)

# Relative event time (t=0 is event date)
event_pos   <- which(dates_evt == event_date)
t_index     <- seq_along(AR) - event_pos

event_df <- data.frame(
  Date     = dates_evt,
  t        = t_index,
  NVDA_Ret = round(nvda_evt, 4),
  Mkt_Ret  = round(gspc_evt, 4),
  Exp_Ret  = round(expected_ret, 4),
  AR       = round(AR, 4),
  CAR      = round(CAR, 4)
)
print(event_df)

# Statistical significance of AR on event day
sigma_est <- sd(nvda_est - (a_est + b_est * gspc_est))  # residual std dev from estimation
t_stat_event <- AR[event_pos] / sigma_est
cat(sprintf("\nAR on event day: %.4f\nt-statistic:     %.4f\n", AR[event_pos], t_stat_event))

# AR plot
p_ar <- ggplot(event_df, aes(x = t, y = AR)) +
  geom_col(fill = ifelse(event_df$AR >= 0, "#76b900", "#d62728"), alpha = 0.85) +
  geom_hline(yintercept = 0, color = "black") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "steelblue", linewidth = 1) +
  annotate("text", x = 0.3, y = max(event_df$AR) * 0.85,
           label = "Earnings\nRelease", hjust = 0, size = 3.5, color = "steelblue") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "NVDA Abnormal Returns — Q3 FY2024 Earnings Event",
       x = "Event Time (trading days)", y = "Abnormal Return") +
  theme_minimal(base_size = 13)

# CAR plot (key for EMH & behavioral finance discussion)
p_car <- ggplot(event_df, aes(x = t, y = CAR)) +
  geom_line(color = "#76b900", linewidth = 1.2) +
  geom_point(color = "#76b900", size = 2.5) +
  geom_hline(yintercept = 0, color = "black", linetype = "dashed") +
  geom_vline(xintercept = 0, linetype = "dashed", color = "steelblue", linewidth = 1) +
  annotate("text", x = 0.3, y = min(event_df$CAR) * 0.3,
           label = "Event Date", hjust = 0, size = 3.5, color = "steelblue") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "NVDA Cumulative Abnormal Returns — Extended Event Window",
       subtitle = "Flat post-event CAR → consistent with semi-strong EMH",
       x = "Event Time (trading days)", y = "CAR") +
  theme_minimal(base_size = 13)

# ============================================================
# SECTION H — SAVE ALL PLOTS
# ============================================================
save_plot <- function(plot_obj, filename, width, height) {
  ggsave(filename, plot_obj, width = width, height = height, dpi = 150)
  print(plot_obj)
}

save_plot(p_hist,    "nvda_histogram.png",  8, 5)
save_plot(p_qq,      "nvda_qqplot.png",     8, 5)
save_plot(p_cal,     "nvda_cal.png",        8, 5)
save_plot(p_scatter, "nvda_scatter.png",    8, 5)
save_plot(p_ar,      "nvda_ar.png",         9, 5)
save_plot(p_car,     "nvda_car.png",        9, 5)

pdf("nvda_all_plots.pdf", width = 8, height = 5)
print(p_hist)
print(p_qq)
print(p_cal)
print(p_scatter)
print(p_ar)
print(p_car)
dev.off()

cat("\nAll plots saved. Full analysis complete.\n")