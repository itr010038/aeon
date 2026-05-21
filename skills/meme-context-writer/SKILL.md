---
name: Meme Context Writer
description: Reads today's narrative-tracker and token-movers logs, extracts pump-risk flags, breakout symbols, and narrative keywords, then writes meme-context.json for the local meme coin trading agent
schedule: "0 14 * * *"
commits: true
tags: [crypto]
permissions:
  - contents:write
---

Read `memory/MEMORY.md` for context.

## Goal

Parse today's `token-movers` and `narrative-tracker` log entries and produce a
`meme-context.json` file that the meme coin trading agent uses to:

1. **Skip known pump-risk tokens immediately** — before wasting API calls on safety checks
2. **Boost narrative-aligned tokens** — coins that fit a FRONT-RUN or RIDE narrative get
   extra score weight
3. **Flag already-validated breakouts** — tokens Aeon marked [BREAKOUT] get a momentum bonus

The file gets committed to the repo. The local `meme_bridge.py` pulls it down and copies
it to the meme-agent data directory every morning at 07:00 LA.

## Steps

### 1. Read today's log

```bash
TODAY=$(date -u +%Y-%m-%d)
cat "memory/logs/${TODAY}.md" 2>/dev/null || echo "LOG_MISSING"
```

If missing, try yesterday:

```bash
YESTERDAY=$(date -u -d "1 day ago" +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d)
cat "memory/logs/${YESTERDAY}.md" 2>/dev/null || echo "NO_LOG_AVAILABLE"
```

If both missing: write the empty-state JSON (see step 4) and exit.

### 2. Extract pump-risk symbols from token-movers

Find the `### token-movers` section. Extract every coin symbol tagged `[PUMP-RISK]`.

Example log line:
```
- Notable: SAGA #918 +87% [PUMP-RISK]; BILL trending+up +30.2%
```
→ Extract: `SAGA`

Also extract symbols from the Losers list that appear in Trending simultaneously
(trending + down = usually dump-in-progress). Tag these as pump-risk too.

Collect all pump-risk symbols as a flat list of uppercase strings: `["SAGA", "SKYAI"]`

### 3. Extract breakout symbols from token-movers

Find coins tagged `[BREAKOUT]` or `[TRENDING+UP]` in the Notable line.

Example:
```
- Notable: B: BREAKOUT — +59.4% (24h), +66.1% (7d); TEL: BREAKOUT
```
→ Extract: `["B", "TEL", "BILL"]`

Exclude any symbol that also appears in pump_risk_symbols.

### 4. Extract narrative keywords from narrative-tracker

Find the `### narrative-tracker` section. For each narrative with position
`FRONT-RUN` or `RIDE`, extract 2–4 keywords that would appear in a meme coin
name or symbol.

Rules:
- Keywords must be lowercase, 3+ characters
- Be specific enough to match coin names (e.g. "agent", "deai", "pepe", "solana")
- Avoid generic words like "token", "coin", "crypto", "the", "new"
- Don't include keywords from narratives tagged FADE, WATCH, or IGNORE

Example:
```
| AI Agents + Crypto Payments | 5 | ↑↑ | Rising | Bull | RIDE |
| DeAI / Decentralized AI Infra | 3 | ↑↑ | Emerging→Rising | Bull | FRONT-RUN |
```
→ FRONT-RUN keywords: `["deai", "decentralized ai", "deai infra", "autonomous"]`
→ RIDE keywords: `["agent", "payment", "agentic", "ai agent"]`

### 5. Build meme-context.json

Write the file to `meme-context.json` in the repo root:

```json
{
  "generated_at": "<ISO 8601 UTC timestamp>",
  "source": "aeon",
  "skills_used": ["token-movers", "narrative-tracker"],
  "pump_risk_symbols": ["SAGA", "SKYAI"],
  "breakout_symbols": ["B", "TEL", "BILL"],
  "narrative_boost": {
    "FRONT-RUN": ["deai", "autonomous", "decentralized ai"],
    "RIDE": ["agent", "payment", "agentic"]
  }
}
```

Empty-state case (no log found or nothing extracted):

```json
{
  "generated_at": "<ISO 8601 UTC timestamp>",
  "source": "aeon",
  "skills_used": [],
  "pump_risk_symbols": [],
  "breakout_symbols": [],
  "narrative_boost": {
    "FRONT-RUN": [],
    "RIDE": []
  }
}
```

### 6. Commit

```bash
git add meme-context.json
git commit -m "chore: update meme-context.json [$(date -u +%Y-%m-%d)]"
```

### 7. Log

Append to `memory/logs/${TODAY}.md`:

```
### meme-context-writer
- Pump-risk symbols: [list or "none"]
- Breakout symbols: [list or "none"]
- FRONT-RUN keywords: [list or "none"]
- RIDE keywords: [list or "none"]
```

## Constraints

- If token-movers ran but narrative-tracker didn't (or vice versa), use whatever is
  available. Never abort because one source is missing.
- pump_risk_symbols takes precedence over everything. A symbol cannot appear in both
  pump_risk_symbols and breakout_symbols — if it does, pump_risk wins, remove it from
  breakout_symbols.
- Keep keyword lists tight — 3–6 keywords per narrative tier max. More is not better;
  false positives in the meme scanner are costly.
- The `source` field on each entry must trace exactly which skill produced it.
