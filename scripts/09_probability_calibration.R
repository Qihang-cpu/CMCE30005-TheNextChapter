# Plot held-out probability calibration after rq_scope_feasibility.py.
# Bin summaries describe uncalibrated scores; no model is fitted here.
library(data.table)
library(ggplot2)
library(scales)

input <- "reports/tables/rq_calibration.csv"
stopifnot(file.exists(input))
cal <- fread(input)[scenario == "property_only"]
stopifnot(nrow(cal) > 0, all(cal$n > 0),
          all(cal$mean_predicted_probability >= 0 & cal$mean_predicted_probability <= 1),
          all(cal$observed_review_target_share >= 0 & cal$observed_review_target_share <= 1))
cal[, model_label := factor(model, levels = c("logistic", "random_forest"),
                            labels = c("Logistic regression", "Random forest"))]
p <- ggplot(cal, aes(mean_predicted_probability, observed_review_target_share)) +
  geom_abline(intercept = 0, slope = 1, linetype = "dashed", colour = "grey50") +
  geom_line(colour = "#236A9F", linewidth = .5) +
  geom_point(aes(size = n), colour = "#236A9F", alpha = .85) +
  geom_text(aes(label = ifelse(n < 50, paste0("n=", n), "")),
            vjust = -1.1, size = 3, colour = "#333333") +
  facet_wrap(~model_label, nrow = 1) +
  scale_x_continuous(labels = label_percent(), limits = c(0, 1)) +
  scale_y_continuous(labels = label_percent(), limits = c(0, 1)) +
  scale_size_area(max_size = 8, breaks = c(50, 500, 1500), name = "Listings in bin") +
  coord_equal() +
  labs(title = "Probability calibration for the primary review-activity models",
       subtitle = "Out-of-fold predictions for analysis hosts | Common benchmark from separate reference hosts",
       x = "Mean predicted probability within bin", y = "Observed benchmark attainment within bin",
       caption = paste0("Ten fixed-width probability bins; empty bins omitted. Dashed line: predicted equals observed.\n",
                        "Labels identify bins with fewer than 50 listings. Sparse bins have substantial sampling uncertainty.\n",
                        "No probability recalibration has been fitted. These scores do not forecast a new operator's future performance.")) +
  theme_minimal(base_size = 11) +
  theme(legend.position = "bottom", panel.grid.minor = element_blank(),
        strip.text = element_text(face = "bold"), plot.title.position = "plot",
        plot.caption = element_text(hjust = 0, size = 9))
dir.create("reports/figures", recursive = TRUE, showWarnings = FALSE)
ggsave("reports/figures/18_probability_calibration.png", p, width = 11.5, height = 6.6, dpi = 150)
