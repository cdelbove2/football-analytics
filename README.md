# Football Analytics Platform

A multi-source football (soccer) analytics platform for transfer scouting: cross-referencing
player data from multiple providers to identify the best players at each position within
defined price brackets, with player/team comparison and watchlist features.

## Why this project

1. **Build something useful** — a scouting/analytics tool with real product value.
2. **Learn a modern data stack** — Postgres, dbt, Python ingestion, GitHub Actions CI/CD,
   pandas/scikit-learn analytics. Graph (Neo4j) and orchestration (Airflow) are deliberately
   deferred until the core pipeline is stable.

## Working principles

See [`docs/principles.md`](docs/principles.md). The short version: this is
a learning project as much as a product, so every component should be
commented to explain *what* it does and *why*, not just left as terse
production-style code.

## Architecture

```
Data sources (FBref, Transfermarkt, Understat, ...)
        |
        v
  ingestion/  (Python scrapers -> raw tables in Postgres)
        |
        v
  dbt/        (staging -> intermediate -> marts)
        |
        v
  analytics/  (pandas/scikit: scoring, clustering, price-bracket ranking)
        |
        v
  api/        (FastAPI, later)
```

## Repo structure

```
football-analytics/
├── ingestion/          # Python scrapers per source
├── dbt/                 # dbt project: staging -> intermediate -> marts
├── analytics/           # pandas/scikit notebooks & scripts
├── api/                  # FastAPI app (later)
├── sql/                  # raw schema DDL, manual migrations
├── .github/workflows/    # CI + scheduled ingestion jobs
└── docs/                 # architecture decisions, data dictionary
```

## Getting started

### 1. Start Postgres locally

```bash
docker compose up -d
```

This starts a local Postgres instance on `localhost:5432` (db: `football`, user/pass: `football`/`football`).

### 2. Create the raw schema

```bash
psql postgresql://football:football@localhost:5432/football -f sql/001_init_raw_schema.sql
```

### 3. Set up Python environment

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r ingestion/requirements.txt
```

### 4. Run the first ingestion script

```bash
python ingestion/fbref_scrape.py
```

### 5. Set up dbt

```bash
pip install dbt-postgres
cd dbt
dbt debug   # check connection (uses profiles.yml / ~/.dbt/profiles.yml)
dbt run
```

## Roadmap

- [x] Project scaffold, raw schema, Postgres via Docker
- [ ] FBref ingestion (first data source)
- [ ] Transfermarkt ingestion (valuations)
- [ ] Player identity mapping table population (tiered matching)
- [ ] dbt staging models
- [ ] dbt intermediate models (cross-source joins via mapping table)
- [ ] dbt marts: position-specific metric sets, price brackets
- [ ] Analytics: scoring composites, similarity clustering (pandas/scikit)
- [ ] GitHub Actions: scheduled ingestion + dbt run + tests
- [ ] FastAPI layer
- [ ] Frontend (radar charts, scout assist, watchlist)
- [ ] (Later) Neo4j for similarity graph
- [ ] (Later) Airflow if pipeline complexity warrants it

## Data sources

| Source | Type | Data |
|---|---|---|
| FBref (StatsBomb-powered) | Free, scrape | Advanced stats, xG |
| Understat | Free, scrape | xG, shot data |
| Transfermarkt | Free, scrape | Market values, transfers, contracts |
| SofaScore | Free, scrape | Ratings, live data |
| Opta / Stats Perform | Paid | Event-level data |
| Wyscout | Paid | Scouting, video |
| SportsRadar | Paid (tiers) | Fixtures, lineups, stats |

See `docs/data_dictionary.md` (TBD) for field-level mapping once ingestion begins.
