---
name: Research Feed Writer
description: Reads today's token-movers and narrative-tracker logs, extracts high-signal coin symbols, and writes research-feed.json for the local spot-HTF trading agent
schedule: "0 9 * * *"
commits: true
tags: [crypto]
permissions:
  - contents:write
---

Read `memory/MEMORY.md` for context.

## Goal

Parse today's `token-movers` and `narrative-tracker` log entries and produce a clean
`research-feed.json` file that the spot-HTF trading agent can consume as its daily watchlist.

The file gets committed to the repo. The local bridge script (`aeon_bridge.py`) then
pulls it down and copies it into the agent's data directory.

## Steps

### 1. Read today's log

```bash
TODAY=$(date -u +%Y-%m-%d)
cat "memory/logs/${TODAY}.md" 2>/dev/null || echo "LOG_MISSING"
```

If the file doesn't exist or is empty, check yesterday's log as a fallback:

```bash
YESTERDAY=$(date -u -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d)
cat "memory/logs/${YESTERDAY}.md" 2>/dev/null || echo "NO_LOG_AVAILABLE"
```

If both are missing, write an empty feed (see step 4 empty case) and exit.

### 2. Extract symbols from token-movers

Find the `### token-movers` section in the log. Extract:

- **Winners**: any coin symbols listed in the Winners line
- **Trending**: any coin symbols listed in the Trending line
- **Exclude** any tagged `[PUMP-RISK]` or `[FADE]` — these are noise, not signal
- **Prioritise** coins tagged `[BREAKOUT]` or `[TRENDING+UP]` — these go in first

Parse the symbols from lines like:
```
- Winners: BTC (+3.2%), ETH (+2.1%), SOL (+5.8%), …
- Trending: HYPE, KAITO, VIRTUAL, …
```

Extract just the symbol part (before the parenthesis or comma).

### 3. Extract symbols from narrative-tracker

Find the `### narrative-tracker` section in the log. Extract coins mentioned under:
- **FRONT-RUN** position calls — highest priority, emerging narrative plays
- **RIDE** position calls — rising narratives, good entry window

Ignore **FADE**, **WATCH**, and **IGNORE** calls entirely.

Parse named tokens from lines like:
```
- FRONT-RUN: AI agents narrative — VIRTUAL, ARC, GRIFFAIN
- RIDE: DeFAI narrative — GRIFFAIN, ARC
```

If the narrative section doesn't name specific tokens (just describes themes), skip it.

### 4. Build the symbol list

Combine all extracted symbols. Apply these rules:

1. Deduplicate (case-insensitive)
2. Remove stablecoins: USDT, USDC, DAI, BUSD, TUSD, FDUSD, USDE, FRAX and anything starting with USD/EUR/GBP
3. Remove BTC and ETH — the agent always watches these, no need to include them
4. Convert to Bybit USDT perpetual format: append `USDT` if not already present
   - `SOL` → `SOLUSDT`
   - `HYPE` → `HYPEUSDT`
   - Already `SOLUSDT` → keep as is
5. Apply known symbol overrides for common Bybit naming differences:
   ```
   SHIB  → 1000SHIBUSDT
   PEPE  → 1000PEPEUSDT
   FLOKI → 1000FLOKIUSDT
   BONK  → 1000BONKUSDT
   ```
6. Cap at **20 coins** — ranked by signal priority:
   - FRONT-RUN coins first
   - BREAKOUT / TRENDING+UP winners next
   - RIDE coins next
   - Other winners/trending last

Assign a synthetic `rvol` for each entry to pass the agent's R-Vol gate (`min_rvol: 2.0`):
- FRONT-RUN coins: `rvol: 3.5`
- BREAKOUT/TRENDING+UP: `rvol: 3.0`
- RIDE: `rvol: 2.5`
- Other movers/trending: `rvol: 2.0`

### 5. Write research-feed.json

Write the file to `research-feed.json` in the repo root:

```json
{
  "generated_at": "<ISO 8601 UTC timestamp>",
  "source": "aeon",
  "skills_used": ["token-movers", "narrative-tracker"],
  "coins": [
    {"symbol": "SOLUSDT", "rvol": 3.0, "source": "aeon:token-movers:BREAKOUT"},
    {"symbol": "VIRTUALUSDT", "rvol": 3.5, "source": "aeon:narrative-tracker:FRONT-RUN"}
  ]
}
```

Empty case (no log, no symbols extracted):

```json
{
  "generated_at": "<ISO 8601 UTC timestamp>",
  "source": "aeon",
  "skills_used": [],
  "coins": []
}
```

### 6. Commit

```bash
git add research-feed.json
git commit -m "chore: update research-feed.json [$(date -u +%Y-%m-%d)]"
```

### 7. Log

Append to `memory/logs/${TODAY}.md`:

```
### research-feed-writer
- Coins written: N
- FRONT-RUN: [symbols]
- BREAKOUT: [symbols]
- RIDE: [symbols]
- Other: [symbols]
```

## Constraints

- Never recommend buying or selling. The `rvol` field is a signal strength proxy, not financial advice.
- If token-movers or narrative-tracker sections are missing from the log, proceed with whatever is available. Don't abort if one source is empty.
- The `source` field on each coin must trace exactly which skill and tag produced it — this is used for debugging and tuning.
