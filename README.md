# Engineering Metrics

Shared GitHub Actions for tracking engineering metrics across Ayunis repositories.

## Metrics

| Metric | Source | Description |
|--------|--------|-------------|
| **PR Size** | additions + deletions | Average, median, distribution (S/M/L/XL) |
| **Cycle Time** | PR opened → merged | Average, median, p90 |
| **Time to First Review** | PR opened → first review | Average, median, p90 |
| **Deployment Frequency** | merges to main + deploy runs | Count and daily rate |
| **Type Distribution** | branch/title prefix | feature, fix, refactor, chore, ci, docs |

## Setup

Copy the example workflow to your repository:

```bash
cp examples/pr-metrics.yml <your-repo>/.github/workflows/pr-metrics.yml
```

Or create `.github/workflows/pr-metrics.yml` with:

```yaml
name: PR Metrics

on:
  pull_request:
    types: [opened, synchronize]
  schedule:
    - cron: "0 7 * * 1"

jobs:
  pr-check:
    if: github.event_name == 'pull_request'
    uses: ayunis-core/engineering-metrics/.github/workflows/pr-check.yml@main
    with:
      size-threshold: 400  # lines changed before warning

  weekly-report:
    if: github.event_name == 'schedule'
    uses: ayunis-core/engineering-metrics/.github/workflows/weekly-report.yml@main
    with:
      days: 7
      # post-to-issue: 42  # optional: post to a tracking issue
```

## How It Works

### PR Check (on every PR)

- Auto-labels PRs by **size**: `size/S` (≤50), `size/M` (51–200), `size/L` (201–400), `size/XL` (>400)
- Auto-labels PRs by **type**: `type/feature`, `type/fix`, `type/refactor`, `type/chore`, `type/ci`, `type/docs`, `type/other`
- Posts a **warning comment** when a PR exceeds the size threshold
- Type is inferred from branch prefix (`feat/`, `fix/`, `refactor/`, ...) or PR title prefix (`feat:`, `fix:`, ...)
- Also recognizes the `MM-DD-type_...` branch naming pattern

### Weekly Report (scheduled)

Generates a markdown report with all five metrics, posted to the GitHub Actions summary tab.
Optionally posts to a tracking issue for easy access.

## Size Buckets

| Label | Lines Changed |
|-------|--------------|
| `size/S` | ≤ 50 |
| `size/M` | 51 – 200 |
| `size/L` | 201 – 400 |
| `size/XL` | > 400 |

## Type Classification

Types are inferred from branch names and PR titles:

| Prefix | Type |
|--------|------|
| `feat/`, `feature/` | feature |
| `fix/`, `bugfix/`, `hotfix/` | fix |
| `refactor/` | refactor |
| `chore/` | chore |
| `ci/` | ci |
| `docs/` | docs |
| *(anything else)* | other |
