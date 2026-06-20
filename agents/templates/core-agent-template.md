# Core Service Agent Overlay
**Applies to:** service, api (goods-price-comparison-{service,api})
**Tech Stack:** Spring Boot 3, Java 21, PostgreSQL, Flyway, Hexagonal Architecture

## Domain Context
- **Domains:** price, product, store, receipt, price-calc, bill-split, stock, promotion
- **Events:** ReceiptEventOutPort (receipt scanned/approved/rejected), PriceEventOutPort (price calculated/updated)
- **Persistence:** JPA entities (Stores, Products, Prices, Receipts, ReceiptApprovals, BillSplits, Stocks, Promotions)
- **Architecture:** `application/` (port + service) + `infrastructure/` (adapter + entity)

## Integration Notes
- Submodule path: `.workflow-engine/`
- opencode.json: uses `sumopod/deepseek-v4-flash` model
- Lean-ctx: `/opt/homebrew/bin/lean-ctx`
- Ponytail intensity: **high** — no unsolicited abstractions, no unvalidated input

## Threshold Overrides
| Gate | Value |
|------|-------|
| Score threshold | 75 |
| Max debt items | 3 |
| SDD gate | always |
