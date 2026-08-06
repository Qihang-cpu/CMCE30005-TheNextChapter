# ============================================================
# CMCE30005 Business Analytics Challenge
# Script: 00_packages.R
# Purpose: Install and load all packages required for this project
# Author: TheNextChapter (Group 2)
# Date: 6 August 2026
# ============================================================

# Install packages (run once - comment out after installation)
# install.packages(c(
#   "tidyverse",    # Data manipulation and visualisation
#   "lubridate",    # Date handling
#   "janitor",      # Data cleaning utilities
#   "skimr",        # Quick data summary
#   "naniar",       # Missing data visualisation
#   "corrplot",     # Correlation matrices
#   "ggcorrplot",   # ggplot2-style correlation matrices
#   "scales",       # Number formatting in plots
#   "patchwork",    # Combining ggplot2 plots
#   "knitr",        # Report generation
#   "rmarkdown"     # R Markdown rendering
# ))

# Load packages used throughout the project
library(tidyverse)
library(lubridate)
library(janitor)
library(skimr)
library(naniar)
library(ggcorrplot)
library(scales)
library(patchwork)

# Session information (for reproducibility)
sessionInfo()
