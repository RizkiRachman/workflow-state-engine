<!-- omit from toc -->
# Goods Price Comparison Service

[![Doc][doc-shield]][doc-url]

## Vision

A modular, event-driven platform for aggregating, comparing, and alerting on goods prices across multiple stores. Enables users to track price history, set price alerts, and leverage LLM-powered receipt analysis.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Tech Stack

- **Language**: Java 21
- **Framework**: Spring Boot 3.4

- **Build**: Maven
- **Architecture**: Hexagonal (ports & adapters) per service, event-driven between services

- **Database**: PostgreSQL (H2 in test)
- **API Spec**: OpenAPI-generated controllers from `goods-price-comparison-api:1.3.0`

- **Quality**: ArchUnit + SpotBugs + PMD CPD + Spotless (Google Java Style) + JaCoCo (target: 90% INSTRUCTION / 80% BRANCH) + Newman/Postman Smoke Tests

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Code Duplication Landscape (2026-06-11, Updated)

Structural duplication patterns identified via GitNexus graph analysis. PMD CPD confirms **zero literal copy-paste** (abstractions work). Several patterns partially addressed in recent PRs (#130-#134):

- **CRUD Service boilerplate** (9 services, ~120 lines) — [OK] **Addressed**: `AbstractGenericService` pattern proven across 5 services (Store, Price, Product, Receipt, Alert). Remaining 4 services have domain-specific logic that resists CRUD abstraction.
- **Web adapter `list()` orchestration** (7 adapters, ~70 lines) — [PARTIAL] **Partially addressed** (PR #133): `buildPageRequest()` helper added to `AbstractCrudWebAdapter`. Core orchestratration pattern still structurally duplicated across 7 adapters.

- **Repository `buildSpecification()`** (4 adapters, ~40 lines) — [PARTIAL] **Partially addressed** (PR #132): `CategoryRepositoryAdapter` normalized to `CategoryCriteria`. Store/Unit adapters still use raw params.
- **Event handler wiring** (5 handlers) — [SKIP] **YAGNI**: ~3 lines/handler annotation duplication. Distinct event types prevent further abstraction (decision: `yagni-eventhandler-wiring`).

- **LLM provider methods** (4 providers) — [SKIP] **YAGNI**: Distinct API schema patterns (Gemini vs Groq vs Ollama vs OpenAI) prevent `parseResponse()` consolidation.
- **Mapper DtoMapperSupport** (4 mappers) — [OK] **Addressed**: Pattern already extracted in PR #129 (`DtoMapperSupport` interface adopted by 5 DTO mappers).

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Improvement Roadmap (2026-06-12)

Prioritized improvement opportunities identified via GitNexus + Graphify + PMD CPD analysis. See `STATE.md` Architecture Improvement Plan for detailed examples and implementation guidance.

| Priority  | Bucket | Pattern                                                                                            | Effort |    Net Lines     |   Status    |
|:---------:|--------|----------------------------------------------------------------------------------------------------|:------:|:----------------:|:-----------:|
|  P1-HIGH  | A      | Controller endpoint wiring helper (`ControllerResponse.created()/ok()/noContent()`)                |  Low   | ~0 (consistency) | 🔲 Proposed |
|  P1-HIGH  | B      | Web adapter `list()` orchestration — add `buildCompleteListResponse()` to `AbstractCrudWebAdapter` |  Low   |       -12        | 🔲 Proposed |
| P2-MEDIUM | C      | Test pattern base class for service-layer "not found" tests                                        | Medium |       -30        | 🔲 Proposed |
| P2-MEDIUM | D      | SpecificationBuilder normalization — StoreCriteria + UnitCriteria                                  |  Low   |        -5        | 🔲 Proposed |
|  P3-LOW   | E      | DtoMapperSupport adoption for AlertDtoMapper, ActivityLogDtoMapper                                 |  Low   |        ~0        | 🔲 Proposed |
|  P3-LOW   | F      | Exception class monitoring (no active change needed)                                               |   —    |        —         | 🔲 Monitor  |

**Legend**: 🔲 Proposed → 🟡 In Progress → 🟢 Done → ⚫ YAGNI

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Architecture (Three-Layer Hybrid)

1. **Microservice boundaries** — 8 services under `com.example.goodsprice`: receipt, price, product, store, llm, shopping, alert, system
2. **Hexagonal per service** — `application/` (pure Java) + `infrastructure/` (Spring adapters)

3. **Event-driven** — Spring ApplicationEvent + @Async + @TransactionalEventListener(AFTER_COMMIT)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- REFERENCE LINKS -->

[doc-shield]: https://img.shields.io/badge/DOC-文档-blue?style=for-the-badge
[doc-url]: #

[docs-shield]: https://img.shields.io/badge/DOCS-文档-blue?style=for-the-badge
[docs-url]: #

[github-shield]: https://img.shields.io/badge/GitHub-181717?style=for-the-badge&logo=github
[github-url]: #

