# CMCE30005 Business Analytics Challenge

## TheNextChapter — Group 2

- **Subject:** CMCE30005 Business Analytics Challenge, Semester 2 2026
- **University:** University of Melbourne
- **Team Members:** EricH896, Qihang-cpu, maksym-xu, Leloc

---

## Business Problem

*Proposed framing — to be confirmed by the team.*

A client intends to list several properties on Airbnb in Melbourne and needs to
decide **where to invest, what property type to operate, and how to price it**.
The stakeholder is the prospective host; the question matters because entry cost
and location are effectively irreversible once committed.

The analysis so far covers market structure, a hedonic price model, demand
seasonality, and revenue by segment. Interim results are in
[reports/findings.md](reports/findings.md), with open questions for the team at the end
of that file.

---

## Dataset

- **Dataset name:** Inside Airbnb — Melbourne
- **Source:** [Inside Airbnb](https://insideairbnb.com)
- **Coverage:** Snapshot of 16 June 2026; active listings across Greater
  Melbourne and surrounding local government areas

### Data Files

| File | Description | Size |
|---|---|---:|
| `listings_airbnb.csv` | One row per active listing, ~90 attributes | 68 MB |
| `calendar_airbnb.csv` | Daily availability, 17 Jun 2026 – 30 Jun 2027 | 361 MB |
| `reviews_airbnb.csv` | All guest reviews, Aug 2010 – Jun 2026 | 266 MB |

> Large raw data files are not committed to this repository. Download the three
> files from Inside Airbnb and place them in `data/raw/`. See
> [reports/data-notes.md](reports/data-notes.md) for the join keys and the data quality
> problems worth knowing before you write any new script.

### Key variables and features


### Limitations and potential problems 


### Assumptions 

---

## Running the Analysis

Open `CMCE30005-Group2.Rproj` so the working directory is the project root, then
run the scripts in order:

```r
source("scripts/00_packages.R")          # once, to install and load packages
source("scripts/01_data_cleaning.R")     # ~2 min, writes data/processed/
source("scripts/02_exploratory_analysis.R")
source("scripts/03_price_model.R")
```

Script 01 additionally requires `data.table` and `stringr`; script 03 requires
`broom`. Charts land in `reports/figures/` and summary tables in
`reports/tables/`, both of which are committed so results can be reviewed
without re-running the pipeline.

---

## Data Understanding

---

## Data Prepration

---

## Modeling 

---

## Evaluation

---

## Project Scope

### Repository Structure 

```text
CMCE30005-Group2/
├── data/
│   ├── raw/        # Source CSVs (not committed - download separately)
│   └── processed/  # Cleaned tables rebuilt by scripts/01 (not committed)
├── scripts/        # R analysis scripts, run in numbered order
├── reports/
│   ├── figures/    # Charts
│   ├── tables/     # Summary tables and model output
│   ├── data-notes.md
│   ├── methodology.md
│   └── findings.md # Interim results
├── README.md
├── .gitignore
└── CMCE30005-Group2.Rproj
```

---
*Last updated: 6 August 2026*
