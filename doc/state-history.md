# Project State

## Current Focus

**LEAN-CTX.md v2 — Complete Tool Inventory + Use Case Mapping.** 2026-06-16.

**State**: COMPLETE. LEAN-CTX.md rewritten from 35 lines to 320+ lines with 10 sections: tool preference, use case matrix, read mode selection, batch ops, knowledge management, session management, tool discovery + ctx_call, compression strategy, cost awareness, and full tool inventory with project-specific use case mapping. 29 lean-ctx tools cataloged across 12 categories. Top 5 underused: ctx_overview (session start), ctx_architecture (diagrams), ctx_compile (subagent prep), ctx_prefetch (refactor prewarm), ctx_callgraph (bug tracing).

**Next**: Use ctx_overview at session start instead of manual STATE.md/PROJECT.md reads. Adopt ctx_prefetch before large refactors. Integrate ctx_compile into subagent dispatch process.

**State**: COMPLETE. 3 skills wired into opencode.json + 4 agent .md files. Skills auto-discoverable via /skill. All 4 agents (tech-lead, system-analyst, developer, quality-analyst) have DDD/SDD/5-axis in their skill arrays + .md load sections.

**Next**: Use the new workflow in real work — DDD for non-trivial decisions, SDD spec gate for multi-file changes, 5-axis review for code quality. The skills are wired and ready for agent sessions.

**Summary**: Produced 827-line implementation specification at `.opencode/planning/addyosmani-integration-plan.md` covering all 24 addyosmani skills, 4 personas, state machine integration with DDD/SDD gates, 5-axis code review, 6 implementation phases over 22 days, risk register, and 6 skill file templates. Key decisions: 7 ADOPT, 10 ADAPT, 6 MERGE, 1 SKIP; no new agents needed; DDD integrated into scoring Tier 1 (30 pts); SDD gate between PLAN_SCORED→EXECUTE (30 pts).

**State**: Native `read`, `edit`, `grep`, `bash` blocked via opencode.json global permission + per-agent tools blocks (11 agents). Agents must use `lean-ctx` equivalents.

**Next**: Verify enforcement works in actual agent sessions.

- Fixed TEST_001: LlmServiceCacheTest uses Assumptions.assumeTrue() instead of System.out.println+return
- Investigated DEAD_CODE_001: AbstractGenericService.findAll() IS called by CategoryService + FeedbackQuestionService — NOT dead code

- 3 issues found in contract, 1 fixed (TEST_001), 1 investigated (DEAD_CODE_001 — confirmed active), 1 deferred (DOC_001 — gap analysis not updated)

**Key finding**: Commit message claimed "update gap analysis" but no gap analysis file was changed. Both DOC_001 (gap analysis update) and envelope persistence were skipped in this iteration.

**Next**: (1) Verify Iteration 3 — fix remaining iteration gaps (DOC_001, envelope persistence). (2) Add .firecrawl/ + benefit.md to .gitignore. (3) New feature work.

**Result**: 6 PRs merged (#140-#145). 1024 tests pass (up from 860), 0 failures, BUILD SUCCESS.

- All Architecture Improvement Plan buckets resolved (6/6: E, D, A, C, B, F)
- Gap Analysis Parts B & C at max (10/10). Part A at 80/100.

- Phase pattern template made Phase 2 ~40% faster per file
- 19 new test files, 116 new test methods across 2 phases

- All quality gates passed first attempt on all 5 PRs — zero rework
- GitNexus: 5,931 symbols, 14,960 edges, 316 clusters, 300 flows

**Next**: (1) Extract AbstractControllerWebMvcTestBase to dedup 10-file setUp() boilerplate (~150-200 lines). (2) Add /benefit.md and /.firecrawl/ to .gitignore. (3) New feature work.

**Result**: 1024 tests pass (up from 952, +72), 0 failures, BUILD SUCCESS. Added 11 new test files with 72 test methods across all 6 remaining services (Receipt, Price, Shopping, ActivityLog, Alert, FeedbackQuestion). Phase 1 + Phase 2 combined: 19 new test files, 116 test methods. All quality gates pass (Spotless, ArchUnit, SpotBugs, PMD CPD).

**Key finding**: Actual scope (6 services, 72 tests) was 2.5x the contracted estimate (4 services, 29 tests) — Price and Receipt were the most complex with 7 custom JPA queries and MultipartFile upload respectively.

**Next**: (1) Part A code quality gaps (Resilience 35/100, Testing 55/100) if traffic grows. (2) New feature work. (3) Extend test base class pattern to save/create positive/negative test methods if 3+ services share identical behavior.

### Previous: Production Readiness (PR #140) — COMPLETE. Branch: `main`.

---

## Architecture Improvement Plan

> **Part A (Code Quality) — COMPLETE** via PR #140. Part B (OpenCode Config) — COMPLETE. **Part C (Service Gaps) — ALL BUCKETS COMPLETE.** All 6 buckets (E, D, A, C, B, F-monitoring) resolved as of 2026-06-13.

### Bucket A: Controller Endpoint Wiring [P1-HIGH] — ✅ COMPLETE (PR #133)

- **Priority**: P1-HIGH — 8 controllers, ~550 lines total, ~70% structural duplication
- **Resolution**: Added `ControllerResponse` utility (created(), ok(), noContent()) — all 8 controllers updated to use it. Consistency achieved.

- **Evidence**: GitNexus shows 70-77% similarity between CategoryController, StoreController, PriceController, ProductController, ReceiptController, UnitController, FeedbackQuestionController, ActivityLogController
- **Pattern** (repeated 8x):

  ```java
  @RestController @RequiredArgsConstructor

  public class XxxController implements XxxApi {

      private final XxxWebAdapter adapter;

      @Override public ResponseEntity<X> createX(CreateXRequest req) {

          return ResponseEntity.status(HttpStatus.CREATED).body(adapter.create(req));

      }

      @Override public ResponseEntity<X> getX(String id) {

          return ResponseEntity.ok(adapter.findById(id));

      }

      @Override public ResponseEntity<XxxListResponse> listXxx(...) {

          return ResponseEntity.ok(adapter.list(...));

      }

      @Override public ResponseEntity<X> updateX(String id, UpdateXRequest req) {

          return ResponseEntity.ok(adapter.update(id, req));

      }

  }

  ```
- **Previous decision** (PR #133, YAGNI): Abstract base controller rejected — 12 OpenAPI interfaces with no common supertype, complex generics required
- **Existing improvements** (PR #133): Standardized to 1-liner `ResponseEntity.ok(adapter.method())`, fixed HTTP 200→201 for creates

- **What remains**: ~5 lines of nearly identical method per endpoint × 4-5 endpoints × 8 controllers
- **Suggested approach**: No class hierarchy — instead, add a `ControllerResponse` helper utility:

  ```java
  // common/web/ControllerResponse.java

  public class ControllerResponse {

      public static <T> ResponseEntity<T> created(T body) {

          return ResponseEntity.status(HttpStatus.CREATED).body(body);

      }

      public static <T> ResponseEntity<T> ok(T body) {

          return ResponseEntity.ok(body);

      }

      public static ResponseEntity<Void> noContent() {

          return ResponseEntity.noContent().build();

      }

  }

  // Controller becomes:

  // return ControllerResponse.created(adapter.create(req));

  // vs current: return ResponseEntity.status(HttpStatus.CREATED).body(adapter.create(req));

  ```
- **Effort**: Low (~1 file, imports in 8 controllers). **Lines saved**: ~0 net (imports trade off) — value is consistency, not line count
- **Verdict**: 🟢 **DO** — quick consistency win, no architectural risk

### Bucket B: Web Adapter `list()` Orchestration [P1-HIGH] — ✅ COMPLETE

- **Priority**: P1-HIGH — 6 adapters, ~70 lines structural duplication
- **Resolution**: `buildCompleteListResponse()` method added to `AbstractCrudWebAdapter` — all 6 applicable adapters (Store, Category, Unit, ActivityLog, FeedbackQuestion, Price) now use the shared pattern. PriceWebAdapter.listProductPrices() refactored to use buildCompleteListResponse() with storeMap closure.

- **Evidence**: CategoryWebAdapter (65L), StoreWebAdapter (96L), UnitWebAdapter (73L), FeedbackQuestionWebAdapter (54L), ActivityLogWebAdapter (71L), PriceWebAdapter (214L) — all repeat the same orchestration
- **Pattern** (repeated 6x):

  ```java
  public XxxListResponse list(Integer page, Integer pageSize, String search,

                              EntityStatus status, String sortBy, String sortOrder) {

      var params = resolvePagination(page, pageSize, sortBy, sortOrder, "name", "asc");

      var pageRequest = buildPageRequest(params);

      // build criteria / call service

      var pageResponse = categoryInPort.findAll(criteria);

      // map + build response

      var data = buildListResponse(pageResponse, mapper::toApi);

      var response = new XxxListResponse();

      response.setData(data.data());

      response.setPagination(data.pagination());

      return response;

  }

  ```
- **Previous progress** (PR #133): Added `buildPageRequest()` + `buildListResponse()` + `ListResponseData` record to `AbstractCrudWebAdapter`
- **What remains**: The 3-line `response.setData/setPagination/return` block repeats identically in 6 adapters. The criteria construction differs per service (category vs store vs unit criteria).

- **Suggested approach**: Add a parameterized `buildPageAndCall()` helper to `AbstractCrudWebAdapter`:

  ```java
  // In AbstractCrudWebAdapter:

  protected <R> R buildListResponse(PageResponse<?> pageResponse,

                                     java.util.function.Function<ListResponseData<?>, R> responseBuilder) {

      // shared pattern

  }

  ```
  Or more practically — extract the response-assembly into a single method since only the mapper changes:

  ```java
  // In AbstractCrudWebAdapter — new method:

  protected <D, R> R buildCompleteListResponse(

          PageResponse<D> pageResponse,

          Function<D, R> mapper,

          java.util.function.BiFunction<List<R>, Pagination, R> responseFactory) {

      var dp = buildListResponse(pageResponse, mapper);

      return responseFactory.apply(dp.data(), dp.pagination());

  }

  ```
  Then each adapter does:

  ```java
  return buildCompleteListResponse(pageResponse, mapper::toApiCategory,

      (data, pagination) -> {

          var r = new CategoryListResponse();

          r.setData(data); r.setPagination(pagination);

          return r;

      });

  ```
- **Effort**: Low. **Lines saved**: ~12 lines (2 lines × 6 adapters). **Value**: Eliminates the exact 3-line response assembly block
- **Verdict**: 🟢 **DO** — small savings, high consistency gain

### Bucket C: Test Pattern Duplication [P2-MEDIUM] — COMPLETE (PR #141)

- **Priority**: P2-MEDIUM — 15+ nearly identical test methods across 10+ test files
- **Status**: COMPLETE via PR #141 — 2026-06-13

- **Resolution**: Created AbstractGenericServiceTest abstract base class with 12 abstract hooks + 4 inherited test methods. 9 service tests updated to extend base class. 15 duplicated NotFoundException test methods removed.
- **Inherited tests**: shouldFindByIdReturnsEntity(), shouldFindByIdThrowsNotFoundWhenMissing(), shouldDeleteByIdDeletesWhenFound(), shouldDeleteByIdThrowsNotFoundWhenMissing()

- **Service tests updated**: ActivityLog, Alert, Category, FeedbackQuestion, Price, Product, Receipt, Store, Unit
- **Result**: 894 tests/0 failures, BUILD SUCCESS

- **Next extension**: Apply same pattern for save/create positive/negative test paths if 3+ services share identical behavior

### Bucket D: SpecificationBuilder Normalization — Store & Unit [P2-MEDIUM]

- **Priority**: P2-MEDIUM — 2 adapters with raw `(String search, String status)` params
- **Evidence**: Category uses `CategoryCriteria` (fixed in PR #132), but `StoreRepositoryAdapter.buildSpecification(String search, String status)` and `UnitRepositoryAdapter.buildSpecification(String search, String status)` still use raw parameters

- **Existing pattern** (PR #132, Category fixed):

  ```java
  // CategoryRepositoryAdapter — fixed pattern:

  private Specification<CategoryEntity> buildSpecification(CategoryCriteria criteria) {

      // ... uses criteria.getSearch(), criteria.getStatus()

  }

  // Tests use CategoryCriteria constructor

  ```
- **Suggested approach**: Apply same fix to Store and Unit:

  ```java
  // StoreRepositoryAdapter:

  private Specification<StoreEntity> buildSpecification(StoreCriteria criteria) {

      // same structure as Category

  }

  // Backward-compat overload:

  private Specification<StoreEntity> buildSpecification(String search, String status) {

      return buildSpecification(new StoreCriteria(search, status, null, null));

  }

  ```
- **Effort**: Low (~2 adapters + 2 test updates). **Lines saved**: ~5 net. **Value**: Consistency across all 3 SpecificationBuilder adapters
- **Verdict**: 🟢 **DO** — quick consistency follow-up to PR #132

### Bucket E: DTO Mapper Divergence [P3-LOW]

- **Priority**: P3-LOW — 4 mappers implement `DtoMapperSupport`, 2 are standalone
- **Finding**: ActivityLogDtoMapper, AlertDtoMapper don't implement `DtoMapperSupport` (exist before the pattern was extracted)

- **Suggested approach**: Adopt `DtoMapperSupport` for the 2 stragglers:

  ```java
  public class AlertDtoMapper implements DtoMapperSupport<AlertSubscription, AlertSubscriptionRequest, AlertSubscriptionResponse> {

      // already has matching methods, just add implements

  }

  ```
- **Effort**: Very low (~2 files, add `implements` + imports). **Lines saved**: 0 (consistency only)
- **Verdict**: 🟢 **DO** when touching those files next

### Bucket F: Exception Class Proliferation [P3-LOW]

- **Priority**: P3-LOW — Recommend monitoring, not active refactoring
- **Finding**: Service-specific exceptions exist (DuplicateReceiptException, etc.) alongside `NotFoundException` with static factories (`.product()`, `.price()`)

- **Existing pattern**:

  ```java
  public class NotFoundException extends RuntimeException {

      public static NotFoundException product(String id) { ... }

      public static NotFoundException price(String id) { ... }

  }

  ```
- **Observation**: Each custom exception carries semantic meaning — consolidating into generic exceptions loses error-type granularity. Current pattern of `NotFoundException` factories for "not found" cases + specific exceptions for non-standard errors is reasonable.
- **Verdict**: 🟢 **MONITOR** — no action needed now

---

### Previous: Production Readiness (PR #140) — COMPLETE. Branch: `main`.

### Changes

- [OK] Structured JSON logging (Logstash Encoder v8.0 + logback-spring.xml, CONSOLE + FILE appenders)
- [OK] CorrelationFilter (OncePerRequestFilter, MDC, sanitization, UUID fallback)

- [OK] LLM propagation (AbstractRestLlmProvider reads MDC correlationId → X-Correlation-ID header)
- [OK] Prometheus actuator endpoint (actuator.properties, health/info/prometheus/metrics)

- [OK] LLM RestTemplate timeouts (30s connect, 60s read, HC5 Timeout API)
- [OK] Admin audit logging (AdminWebAdapter + LogSanitizer.sanitize())

- [OK] SizeAndTimeBasedRollingPolicy (500MB max, 10GB cap, 30-day retention)
- [OK] Code review: 8 findings fixed (1 CRITICAL, 2 HIGH, 2 MEDIUM, 2 CodeQL)

- [OK] 11 files changed, 6 new tests, 860 tests pass
- [OK] Gap analysis updated: Part A 65→80/100

### Decisions

- Circuit breaker, retry, bulkhead deferred (YAGNI: low traffic <100 req/min)
- Auth/CSRF deferred (YAGNI: public API, no user accounts, no PII)

- Distributed tracing deferred (add with OpenTelemetry when scaling)
- Actuator auth deferred (pre-prod item, not blocking)

---

### Previous: Web Adapter + Controller Consolidation — COMPLETE. Branch: `feature/20260611-web-controller-consolidation`. Envelope: `web-controller-consolidation` (COMPLETE).

### Changes

- [OK] Added `buildPageRequest(PaginationParams)` helper to `AbstractCrudWebAdapter` — adopted by 5 adapters
- [OK] Fixed StoreWebAdapter pagination anomaly (raw helpers → `resolvePagination()` with proper defaults)

- [OK] Standardized 5 controllers to 1-liner `return ResponseEntity.ok(adapter.method())` pattern
- [OK] Fixed StoreController.createStore and ProductController.createProduct: HTTP 200→201 (REST-correct)

- [OK] Fixed ReceiptController `.ok().body()` redundancy
- [OK] Import cleanup: +2 imports (HttpStatus, PageRequestDto), 6 stale imports removed

- [OK] 14 files, +60/-59 lines (net -25 lines after accounting for new test plus helper)
- [OK] 860 tests pass, 0 failures

- [OK] Code review: 82/100 PASS (FLAG on StoreWebAdapter sort default change — acknowledged as intentional UX improvement)

### Decisions

- `buildListResult()` generic helper REJECTED (OpenAPI ListResponse DTOs share no common supertype)
- Abstract base controller REJECTED (12 different OpenAPI interfaces, controllers <90 lines)

---

## Previous: Duplicate Code Consolidation — COMPLETE.** Branch: `feature/20260610-duplicate-code-consolidation`. Envelope: `duplicate-code-consolidation` (COMPLETE).

### Status: All 6 patterns implemented, reviewed, and verified.

- [OK] **Pattern A**: LLM prompt dedup — `RECEIPT_EXTRACTION_PROMPT` constant in LlmConstants
- [OK] **Pattern B**: Entity mappers → MapStruct (AlertMapper, ActivityLogMapper, ReceiptMapper)

- [OK] **Pattern C**: BaseTimestampEntity @MappedSuperclass — 8 entities extend it
- [OK] **Pattern D**: AbstractRepositoryAdapter constructor consolidation — 10 adapters use super()

- [OK] **Pattern E**: DTO mappers → MapStruct (5 mappers: Alert, Price, ActivityLog, Category, Unit)
- [OK] **Pattern F**: DtoMapperSupport adoption (ReceiptDtoMapper, BillSplitDtoMapper)

- [OK] **Code review**: 1 CRITICAL fixed (missing @CreationTimestamp/@UpdateTimestamp) → re-verified
- [OK] **Quality gates**: 859 tests/0 failures, PMD, SpotBugs, ArchUnit, Spotless all pass

- [OK] **39 files changed (+246/-482, ~428 lines saved)**

### Selected Refactoring Targets (6 patterns, ~428 lines savings)

| Pattern | Target | Difficulty | Lines Saved |
|---------|--------|-----------:|:-----------:|
| A | LLM prompt/parseResponse dedup (GeminiLlmProvider ↔ AbstractRestLlmProvider) | Easy | ~80 |
| B | Entity mappers manual → MapStruct (Alert, ActivityLog, Receipt + ReceiptItem inline) | Easy | ~117 |
| C | BaseTimestampEntity @MappedSuperclass (9 entities) | Medium | ~63 |
| D | AbstractRepositoryAdapter constructor consolidation (10 adapters) | Medium | ~160 |
| E | DTO mappers manual → MapStruct (5 mappers) | Easy | ~60 |
| F | DtoMapperSupport adoption (ReceiptDtoMapper, BillSplitDtoMapper) | Easy | ~8 |

## Previous Focus

**OpenCode Configuration Audit — Complete.** Branch: `feature/20260610-config-audit-fixes`.

### Status: 12/12 findings resolved

**DONE:**

- [OK] CRITICAL #1 — API keys → env vars (`${SUMOPOD_API_KEY}`, `${OPENROUTER_API_KEY}`)
- [OK] CRITICAL #2 — orphan `keep-it-simple` removed from architect/code-reviewer + AGENTS.md

- [OK] CRITICAL #3 — agent .md files created for explorer, fixer, librarian
- [OK] HIGH #5 — superpowers plugin → git spec

- [OK] HIGH #6 — circular fallback models fixed (all agents → `openrouter/free`)
- [OK] HIGH #7 — orchestrator trimmed from 10 to 4 core skills

- [OK] MEDIUM #8 — already resolved (librarian on deepseek-v4-flash)
- [OK] MEDIUM #9 — Envelope schema sync: updated `SKILL.md` Envelope Shape to match `template.json` (added `scope.boundary`, `scope.max_parallel_agents`, `validation` block, `decisions.coding_standard`, `governance.*` expanded, `outputs.architecture`/`agent_reports`, `score.rules`/`score.judge`, `retry.score_threshold`/`escalation_threshold`, `metrics.cost_tokens`/`elapsed_ms`)

- [OK] MEDIUM #10 — `MEMORY_API_KEY` → `${MEMORY_API_KEY}`, `DATABASE_URL` → `${PG_MCP_URL}`
- [OK] LOW #12 — Created `.opencode/README.md` documenting `oh-my-opencode-slim`, `@razroo/opencode-model-fallback`, and `superpowers` plugins with agent wiring table

**Previous Focus — OpenCode Config Gap Fixes:**

- [OK] Part B score: 7.7/10 → 10/10
- [OK] 7 actionable gaps fixed (B1-B4, B7-B8)

- [OK] Gap analysis updated in `.opencode/reports/gap-analysis.md`

## Previous Focus — Native Tool Blocking (2026-06-15)

**Score**: 100/100. Branch: `feature/20260615-agent-compliance-audit`.

### Status

- **opencode.json**: Global `permission` block updated — `read`, `edit`, `grep` denied. All 11 agents have `read: false, edit: false, grep: false, bash: false` in tools blocks.
- **AGENTS.md §1.3**: Updated with BLOCKED labels, removed native `read` exception, added `bash` and `grep` as BLOCKED.

- **rules.json**: `READ_001`/`EDIT_001` upgraded from HIGH/FLAG to CRITICAL/BLOCK. `GREP_001` added as CRITICAL/BLOCK.
- **Skills**: `token-optimize/SKILL.md` stale `grep`/`read` references updated to `lean-ctx ctx_search`/`ctx_read`.

- **Enforcement model**: Global `permission` deny + per-agent tools blocks (defense-in-depth). Native `write` allowed for new files. Native `glob` allowed as fallback.

### Key Decisions

- Tools blocked globally (affects orchestrator too, not just subagents)
- Files remain gitignored (local workstation enforcement only)

- Orchestration contract updated to v0.7.1 with COMPLETE state

## Known Blockers

None.

**All config audit findings resolved.** See Completed Work for details.

## Learner Analysis — Bucket B (2026-06-13)

**Architecture Improvement Plan — Bucket B (Web Adapter list() Orchestration) — COMPLETE.** Score: 95/100.

- **What went well**: Single-file refactor (PriceWebAdapter.listProductPrices()) — minimal blast radius. Consistent with 5 other adapters already using the pattern. Planner correctly identified Buckets E, D, A were already done — no wasted analysis.
- **What went well**: Quality gates all green on first attempt — 894 tests/0 failures, ArchUnit PASS, SpotBugs PASS, PMD CPD PASS, Spotless PASS. Code review: 0 findings across all 4 lenses.

- **What went well**: All 6 Architecture Improvement Plan buckets now resolved (E, D, A, C, B, F-monitoring). Gap Analysis Part C score improves from 9.2/10 to 10/10.
- **What went wrong**: `.firecrawl/` and `benefit.md` files from Firecrawl CLI operations still appearing in git tracking — should be in .gitignore to prevent cross-branch noise.

- **What went wrong**: `buildCompleteListResponse()` lambda `(data, pagination) -> { var res = new XxxListResponse(); res.setData(data); res.setPagination(pagination); return res; }` is still boilerplate — unavoidable due to varying OpenAPI ListResponse DTOs (no common supertype).
- **What to change**: (1) Add `.firecrawl/` and `benefit.md` to .gitignore. (2) Commit uncommitted PriceWebAdapter changes and push. (3) Future refactoring — focus on Part A code quality gaps (Testing 55/100: Testcontainers, @WebMvcTest slices; Resilience 35/100: circuit breaker/retry if traffic grows).

- **Knowledge persisted**: bucket-b-web-adapter-complete (architecture/decision), buildCompleteListResponse-pattern (architecture/pattern), architecture-improvement-plan-complete (architecture/decision), firecrawl-noise-files-in-br (gotcha — updated).
- **Envelope**: `orchestration-contract` updated with state=COMPLETE, all 6 buckets complete.

## Learner Analysis — PR #141 (2026-06-13)

**Bucket C: Test Pattern Dedup + Agent Orchestration State Machine — COMPLETE.** Score: 100/100.

- **What went well**: Template Method pattern in AbstractGenericServiceTest worked perfectly — 12 abstract hooks, 4 inherited tests, 15 duplicated methods removed across 9 service tests. Zero test failures (894 pass).
- **What went well**: All quality gates passed on first attempt — 894 tests, 0 failures, BUILD SUCCESS (Spotless, PMD, SpotBugs, ArchUnit). No rework needed.

- **What went well**: Parallel work streams combined efficiently — agent state machine (rules.json + 10 agent definitions) + test dedup in single commit.
- **What went well**: Zero-risk dead code deletion — SpecificationBuilder.java removed with 0 impact. DtoMapperSupport normalization (Price, Shopping, Store) completed.

- **What went wrong**: `.firecrawl/` and `benefit.md` files from Firecrawl CLI operations were tracked in the git diff — should be in .gitignore to avoid noise in future branches.
- **What to change**: Add `.firecrawl/` to .gitignore before new work branches. Extend test dedup pattern to save/create positive/negative test paths if 3+ services share identical behavior.

- **Knowledge persisted**: abstract-test-base-class-pattern (architecture), agent-state-machine-enforcement (architecture), bucket-c-test-dedup-complete (architecture/decision), firecrawl-noise-files-in-branch (gotcha).
- **Envelope**: `orchestration-contract` updated with state=COMPLETE, PR #141 lessons appended.

## Learner Analysis — PR #140 (2026-06-12)

**Production Readiness Features — MERGED.** Structured JSON logging, correlation tracking, Prometheus metrics, LLM timeouts, admin audit logging.

- **What went well**: Code review caught 8 issues before merge (1 CRITICAL: correlation ID not propagated to LLM calls; 2 CodeQL: log injection + deprecated API). All fixed pre-merge — systematic review prevented production incidents.
- **What went well**: Defense-in-depth security — CorrelationFilter sanitizes HTTP headers (preventing response splitting), AdminWebAdapter uses LogSanitizer.sanitize() (preventing log injection), both with UUID fallback for empty inputs. Two independent sanitization layers on different attack surfaces.

- **What went well**: Clean commit history with 13 semantic commits. Fixed the HC5 Timeout API migration (deprecated → modern API) as a dedicated fix commit rather than squashing it into the feature commit.
- **What went wrong**: Actuator `/prometheus` endpoint exposed without auth — documented as pre-prod debt but unresolved. Should add `management.endpoint.prometheus.roles=ADMIN` or Spring Security filter before production deployment.

- **What went wrong**: No test for the CodeQL log injection fix in AdminWebAdapter. The sanitize(jobName) change was verified via diff review but has no dedicated test covering the audit logging behavior.
- **What to change**: For production readiness features, include security review in the initial implementation plan (not as a post-hoc code review finding). The 2 CodeQL issues and 1 CRITICAL correlation gap would have been caught earlier with a security checklist: (1) Are user-controlled inputs sanitized? (2) Is MDC context propagated to async/outbound calls? (3) Are actuator endpoints authenticated?

- **Knowledge persisted**: correlation-filter-pattern (architecture), structured-json-logging-pattern (architecture), hc5-timeout-api-pattern (architecture), correlation-id-llm-propagation (gotcha/critical).
- **Envelope**: `orchestration-contract` updated with state=COMPLETE, PR #140 lessons appended.

## Learner Analysis — PR #134 (2026-06-11)

**Dependabot Security PR Consolidation — COMPLETE.** Consolidated 7 Dependabot PRs into single feature branch. Score: 100/100.

- **What went well**: Bulk merge saved ~70% overhead (avoided 6 PR reviews/CI cycles). Only 1 merge conflict (adjacent YAML lines in ci-publish.yml) — resolved correctly. All quality gates passed (860 tests/0 failures, SpotBugs 0).
- **What went well**: Orchestrator correctly adapted plan mid-execution based on user feedback (sequential → bulk merge).

- **What went wrong**: GitHub Actions adjacent-line version bumps (actions/checkout + actions/setup-java) cause merge conflicts even when functionally independent.
- **What to change**: For Dependabot bulk merges: (1) ask if bulk preferred, (2) merge workflow bumps first, (3) then pom.xml bumps — minimizes conflict risk.

- **Knowledge persisted**: dependabot-bulk-merge-process (pattern), github-actions-adjacent-bump-conflict (gotcha), dependabot-consolidation-strategy (decision).
- **Envelope**: `orchestration-contract` updated with state=COMPLETE, lessons appended.

## Learner Analysis — PR #133 (2026-06-11)

**Web adapter list() + controller CRUD consolidation.** Score: 82/100 PASS.

- **Knowledge persisted**: yagni-abstract-base-controller (decision), yagni-listresponse-generic-helper (decision) — both rejected as over-engineering.
- **What to change**: Web adapter list() orchestration still has structural duplication across 7 adapters. Evaluate next-cycle if line savings ≥100.

## Learner Analysis — PR #132 (2026-06-11)

**Remaining Duplicate Code Consolidation — COMPLETE.** 3 patterns addressed (cache constants + buildSpecification normalization).

- **Knowledge persisted**: cache-constant-adoption-pattern (architecture), buildspecification-criteria-normalization (architecture), yagni-eventhandler-wiring (decision), yagni-specificationhelper (decision).
- **Lesson**: CacheConfiguration is the single source of truth for all cache names — always check before adding string literals to @Cacheable annotations.

## Learner Analysis — PR #131 (2026-06-10)

**Analysis complete**: 6 knowledge artifacts persisted to lean-ctx (3 gotchas, 3 patterns/decisions), orchestrator envelope created, handoff pack created.

- **Gotchas persisted**: mapstruct-mappers-getmapper-test-fix (warning), timestamp-annotation-consolidation-base-entity (critical), base-timestamp-entity-type-mismatch-exclusion (info)
- **Patterns persisted**: duplicate-code-pattern-approach (A-F methodology), mapstruct-interface-conversion-pattern, base-timestamp-entity-consolidation, abstract-repository-adapter-consolidation

- **Decisions persisted**: parse-response-not-consolidated (YAGNI), feedbackquestion-excluded-from-basetimestampentity (OffsetDateTime vs LocalDateTime type mismatch), pmd-abstract-class-suppression-pattern
- **Lesson to change next time**: Always run `rg 'new.*[Mm]apper' src/test/` to catch test instantiation changes after manual→MapStruct conversions. Always audit entity annotations (`rg 'CreationTimestamp|UpdateTimestamp' src/main/`) before/after base class consolidation.

- **Envelope**: `orchestration-contract` created with state=COMPLETE

## Superpowers & MCP Contract

Central contract at `.opencode/orchestration/superpowers-contract.json`. Persisted in lean-ctx as `architecture/superpowers-contract`. All agents MUST load this at session start.

**5 Plugins**: oh-my-opencode-slim (agent framework), @razroo/model-fallback, superpowers (15 skills), opencode-snip (DENIED), opencode-notify

**15 Superpowers Skills**: brainstorming, writing-plans, TDD, subagent-driven-dev, systematic-debugging, verification-before-completion, simplify, using-git-worktrees, dispatching-parallel-agents, executing-plans, finishing-a-branch, request/receive code review, using-superpowers, writing-skills

**5 MCPs**: gitnexus (code intelligence), graphify (knowledge graph), lean-ctx (memory/persistence), context7 (library docs), postgres (database)

**Startup Protocol**: `step_0: create branch → step_1: load skills → step_2: load envelope → step_3: sync state → step_4: refresh gitnexus`

---

## Active Decisions

- Orchestrator: Shared JSON envelope at `.opencode/orchestration/template.json`, persisted via `lean-ctx ctx_knowledge` key `orchestration-contract`
- All subagents (planner, task-manager, code-reviewer, learner) read envelope at session start

- Generic service pattern proven across 5 services (Store, Price, Product, Receipt, Alert). YAGNI strategy: pattern safe for any service whose domain logic does not conflict with inherited save()/findById()/deleteById()
- **consolidation cycle detection rule**: Before injecting InPort into a service during consolidation, check: does the service implementing that InPort already depend on the consolidated service? If yes → cycle detected, use RepositoryPort directly instead. Validated on ReceiptApprovalService/ReceiptCorrectionService reversion.

## Completed Work

- **2026-06-12: Gap Analysis Update** — Updated Part A scores: 65→80/100 (Observability 20→75, Security 15→40, Resilience 10→35, Spring Boot 4.x 40→70). Answered open questions (public API, low traffic, LLM providers). Resolved contrarian views. Updated contrarian views and open questions sections.
- **2026-06-12: Production Readiness Features (PR #140)** — Added structured JSON logging (Logstash Encoder + logback-spring.xml with CONSOLE + FILE appenders, SizeAndTimeBasedRollingPolicy), request correlation tracking (CorrelationFilter extends OncePerRequestFilter with MDC + sanitization + UUID fallback + LLM propagation in AbstractRestLlmProvider), Prometheus metrics endpoint (actuator.properties), LLM RestTemplate timeouts (30s connect, 60s read using HC5 Timeout API), admin module audit logging (AdminWebAdapter + LogSanitizer). Fixed 8 code review findings (1 CRITICAL, 2 HIGH, 2 MEDIUM, 2 CodeQL). 11 files changed, 6 new tests (5 CorrelationFilter + 1 timeout), existing 860 tests pass. Knowledge persisted: correlation-filter-pattern, structured-json-logging-pattern, hc5-timeout-api-pattern, correlation-id-llm-propagation gotcha.

- **2026-06-11: Dependabot Security PR Consolidation (PR #134)** — Consolidated 7 Dependabot PRs into single feature branch. Resolved 1 merge conflict. 860 tests/0 failures, all quality gates pass. Knowledge persisted: dependabot-bulk-merge-process (pattern), github-actions-adjacent-bump-conflict (gotcha), dependabot-consolidation-strategy (decision).
- **2026-06-11: Web adapter list() + controller CRUD consolidation (PR #133)** — Consolidated structural duplication across 14 files (+60/-59 lines). 860 tests pass, 0 failures. Score: 82/PASS.

- **2026-06-11: Remaining Duplicate Code Consolidation** — Envelope: `duplicate-code-remaining-consolidation` (COMPLETE). 3 patterns addressed.

  - **Learner Analysis**: 4 knowledge artifacts persisted (cache-constant-adoption-pattern, buildspecification-criteria-normalization patterns; yagni-eventhandler-wiring, yagni-specificationhelper decisions). No gotchas — all changes were straightforward string-to-constant and signature normalizations that compiled and tested cleanly.

- **2026-06-10: OpenCode Configuration Audit (12/12 findings resolved)** — Full audit of skills, agents, MCPs, plugins, permissions. 3 CRITICAL, 4 HIGH, 4 MEDIUM, 1 LOW — all resolved. Key fixes: API key env-var-ification, orphan skill removal, agent .md creation, plugin git-spec swap, circular fallback fix, orchestrator skill trim, librarian model swap, envelope schema sync (`SKILL.md` ↔ `template.json`), hardcoded credential cleanup, plugin documentation (`.opencode/README.md`). Findings persisted in lean-ctx `gotchas/config-audit-2026-06-10`.
- **2026-06-10: OpenCode Per-Agent Scope Optimization (Approach B)** — Envelope: opencode-per-agent-scope, COMPLETED. 9 agents scoped: per-agent temperature=0/top_p=1, per-agent reasoningEffort (high for orchestrator/planner/task-manager/code-reviewer/oracle, medium for explorer/librarian/fixer/learner), per-agent tools globs disabling unused MCPs, per-agent permission.skill whitelists. Global: compaction.{auto, prune, reserved:8000}, setCacheKey on deepseek-v4-flash. 3 spec errors caught by @planner audit (planner needs gitnexus/graphify, learner needs memory, skill whitelists too narrow). Backup at opencode.json.pre-optimization. 83/83 code-review checks pass. Estimated input token cost reduction: 40-55% via stack of DeepSeek auto-cache + per-agent scope + deterministic settings.

- **2026-06-10: Java 21 Optimization (PR #130)** — Envelope: java21-generic-optimization, COMPLETED. 27 of 30 findings resolved (3 deferred Phase 3). 2 commits (Phase0+remaining, Phase1) + 1 post-merge SpotBugs fix. 39 files changed (+316/-229). Java 21 idioms: HexFormat.of().formatHex(), getFirst(), @Slf4j logger consolidation. New sentinel objects: ShoppingSavingsDomain.ZERO, ShoppingOptimizationResult.EMPTY. New utilities: CollectorUtils, EnumParser, LogSanitizer, DateUtils null-guard, StoreMapBuilder. Refactors: PriceWebAdapter doSearch boolean flag split, ReceiptService catch merge, ProductService delegation, AbstractAsyncPriceCalcHandler. 859 tests, 0 failures. **Post-merge fix**: SpotBugs EI_EXPOSE_REP false positive on ListResponseData record — added targeted suppression in config/spotbugs/exclude.xml. Knowledge: 15 new lessons persisted (hexformat, getfirst, logger-consolidation, sentinel-object, boolean-flag-split, spotbugs-false-positive, utility-extraction, abstract-event-handler, archunit-hexagonal-fix, catch-merge, phase3-deferred).
- **2026-06-10: Generic Consolidation — Shared Abstractions (All 11 Modules)** — Envelope: generic-consolidation-all, COMPLETED. Foundation → Parallel → Verify. 3 foundation files: AbstractCrudWebAdapter (resolvePagination+buildListResponse), DtoMapperSupport, EntityMapperConfig. 5 web adapters, 5 DTO mappers, 7 persistence mappers, 2 receipt services, 3 tests updated. 25 files changed (+218/-179) across 11 modules. ~200 lines of boilerplate eliminated. 859 tests, 0 failures. PR #129 merged. **Post-merge fixes**: Reverted ReceiptInPort injection in ReceiptApprovalService and ReceiptCorrectionService (circular dependency: ReceiptService → ReceiptService does not need to inject its own port). Fixed 6 resolvePagination() test calls with new 6th arg defaultSortOrder, removed stale 5-param override. Knowledge: 3 new lessons persisted (circular-dependency-port-injection gotcha, test-migration-method-overload-removal pattern, consolidation-cycle-detection-checklist pattern).

- **2026-06-10: Generic Service Phase 2 Cleanup (PR #128)** — 9 findings (8 fixed, 1 intentionally skipped). 3 batches, 3 commits, 11 files changed. 859 tests pass, score 95/PASS.

  - Batch1 CRITICAL: null guard in findById(), save() logging demotion, dead NotFoundException.alert(), blanket catch split
  - Batch2 HIGH: @FunctionalInterface restore, findAll→findAllProducts rename

  - H1 (inherited deleteById in upload()) intentionally skipped — entity already fetched via findByHash()
  - Batch3 MEDIUM: @Transactional on parent deleteById, removed 3 boilerplate overrides

  - Knowledge persisted: inherited-delete-redundant (gotcha), annotation-loss-on-delete (gotcha), batch-parallelization (pattern), deleteById-transactional (architecture), delete-pattern-choice (convention)

## Learner Analysis — Iteration 2 (2026-06-13)

**Iterative Dev Cycle — Iteration 2: Dead code investigation + test anti-pattern fix.** Score: 85/100.

Branch: `feature/20260613-iterative-dev-cycle-iteration2`. PR: #147.

- **What went well**: Iteration cycle correctly identified 3 issues from the contract (DEAD_CODE_001, TEST_001, DOC_001) — systematic issue scanning works.
- **What went well**: DEAD_CODE_001 was properly investigated via gitnexus impact analysis — confirmed AbstractGenericService.findAll() IS called by CategoryService:45 and FeedbackQuestionService:45. Marked as NOT dead code, no deletion performed. Correctly avoided a breaking change.

- **What went well**: TEST_001 fix was correct — `Assumptions.assumeTrue()` is the proper JUnit 5 idiom vs `System.out.println()+return`. Quality gates confirmed: 1024 tests, 0 failures, BUILD SUCCESS.
- **What went wrong**: Commit message says "update gap analysis" but git diff shows only LlmServiceCacheTest.java changed (1 file, 6 lines). Gap analysis was NOT updated. Empty promise in commit message.

- **What went wrong**: DOC_001 (Bucket C status in gap analysis still showing OPEN) was identified but NOT fixed. The gap analysis `.opencode/reports/gap-analysis.md` still shows Bucket C as 🟡 EVALUATE — should be ✅ DONE (resolved in PRs #141 and #145).
- **What went wrong**: Orchestration contract envelope was NOT updated during this iteration. The lean-ctx contract still shows the previous actuator task. The iteration 2 contract was initialized in PLAN but never advanced to EXECUTE or COMPLETE.

- **What to change**: (1) Verify commit message accuracy by running `git diff --cached` before finalizing commit messages. (2) Update gap analysis after every iteration — don't claim it in commit messages without actually doing it. (3) Persist orchestration contract envelope after EVERY iteration milestone, not just at init.
- **Knowledge persisted**: junit5-assumptions-over-system-out (gotchas/info), deprecated-findall-still-used (gotchas/W), commit-message-gap-analysis-empty-promise (gotchas/W).

- **Envelope**: `orchestration-contract` updated with state=COMPLETE, Iteration 2 lessons appended.

## Recent Changes

- 2026-06-16: **addyosmani/agent-skills Wiring COMPLETE** — 3 skills (doubt-driven-development, spec-driven-development, code-review-and-quality) installed at `.opencode/skills/*/SKILL.md`. Wired into opencode.json agent skill arrays for tech-lead, system-analyst, developer, quality-analyst. Updated 4 agent .md files with DDD anti-rationalization tables (system-analyst §4, developer §5.5, quality-analyst workflow §7), SDD spec gate between PLAN_SCORED→EXECUTE (tech-lead §2.5, system-analyst §5 spec mode), and 5-axis review framework replacing old 4-lens model (quality-analyst). Knowledge persisted: addyosmani-wiring-complete, agent-skill-wiring-pattern.
- 2026-06-16: **Tech-Lead as Default Primary Agent** — Added `"agent": "tech-lead"` to top-level `opencode.json`. Main chat now defaults to tech-lead agent config (read-only native tools, orchestrator delegation capability, humanizer + firecrawl skills).

- 2026-06-13: **PR #147 — Iteration 2: Test anti-pattern fix (COMPLETE)** — Fixed LlmServiceCacheTest to use Assumptions.assumeTrue() instead of System.out.println+return. Investigated DEAD_CODE_001 (AbstractGenericService.findAll — confirmed NOT dead, called by CategoryService and FeedbackQuestionService). 1 file changed, 1024 tests/0 failures.
- 2026-06-13: **PR #145 — Bucket C Test Pattern Dedup (Controller + Repository Adapter) COMPLETE** — Created AbstractControllerWebMvcTest (64 lines: setUp, ObjectMapper, MockMvc, GlobalExceptionHandler, toJson) and AbstractRepositoryAdapterDataJpaTest (34 lines: @SpringBootTest, @Transactional, EntityManager, getRepository()). Refactored 10 WebMvcTest + 9 DataJpaTest files. 23 files changed, +205/-405 = -299 lines net. 1024 tests/0 failures. Pattern proven across 3 test layers (service, controller, persistence).

- 2026-06-13: **Cross-Session Learning COMPLETE** — 6 PRs merged (#140-#145) across 4 days (June 10-13). Session accomplishments: 164 new tests (860→1024), all 6 Architecture Improvement Plan buckets resolved, Gap Analysis B+C at max (10/10), GitNexus 5,911 symbols. 6 new knowledge artifacts persisted to lean-ctx: firecrawl-gitignore-persistent (gotcha), test-estimation-custom-jpa-queries (gotcha), webmvctest-setup-dedup-opportunity (pattern), phase-pattern-template-accelerates (pattern), quality-gates-first-pass-pattern (pattern), learner-analysis-session-complete (architecture). All quality gates verified: 1024 tests/0 failures, BUILD SUCCESS.
- 2026-06-13: **Cross-Session Learner Analysis — PRs #140-#145 COMPLETE** — Full structured report produced. Key findings: (1) Phase Pattern Template accelerates multi-phase work ~40%, (2) First-pass quality across all 5 PRs — zero rework, (3) Envelope governance gap — envelope stale during EXECUTE in 5/6 PRs, (4) Firecrawl noise files persist across 4+ branches — still not in .gitignore, (5) Test scope estimation 2.5x off — must count custom JPA query methods. 7 new knowledge artifacts persisted: cross-session-analysis-2026-06-13 (architecture), first-pass-quality-pattern (pattern), phase-pattern-template-accelerates (pattern — updated), test-estimation-custom-jpa-queries (pattern), test-boilerplate-dedup-estimation-drift (gotcha/info), firecrawl-gitignore-persistent (gotcha — updated), orchestration-envelope-stale-during-exec (gotcha/critical). Next session priorities: (P0) Add .firecrawl/ + benefit.md to .gitignore, (P1) Enforce envelope updates during EXECUTE, (P1) Part A Testing 55/100 improvements, (P2) Resilience4j circuit breaker if traffic grows.

- 2026-06-13: **Testing Improvements Phase 1 COMPLETE** — 8 new test files (44 test methods) across 4 core services (Category, Store, Unit, Product). Pattern: @SpringBootTest+@Transactional for JPA repository tests; MockMvcBuilders.standaloneSetup() for controller tests (Spring Boot 4.0.6 lacks slice annotations). 952 tests/0 failures, BUILD SUCCESS. Score: 95/100 PASS. Code review: 1 medium (FQN inline), 1 low (method name). Knowledge: 1 pattern, 1 gotcha, 1 decision.
- 2026-06-13: **Bucket B — Web Adapter list() Orchestration COMPLETE** — PriceWebAdapter.listProductPrices() refactored to use buildCompleteListResponse() from AbstractCrudWebAdapter. All 6 applicable adapters now use the shared pattern. Single-file change, 0 findings across all code review lenses. All 6 Architecture Improvement Plan buckets now resolved (E, D, A, C, B, F-monitoring). Knowledge: 4 artifacts persisted. Gap analysis Part C: 10/10.

- 2026-06-13: **PR #141 — Bucket C Test Pattern Dedup + Agent Orchestration State Machine** — Created `AbstractGenericServiceTest` base class (12 abstract hooks + 4 inherited tests), updated 9 service tests, removed 15 duplicated NotFoundException test methods. Added PREFLIGHT_003 state validation to rules.json + agent_states mapping for 10 agents. Deleted dead code (SpecificationBuilder + test). Normalized DtoMapperSupport adoption (Price, Shopping, Store). 894 tests/0 failures, BUILD SUCCESS. Knowledge: 3 patterns, 1 decision, 1 gotcha.
- 2026-06-12: **Gap Analysis Updated** — Part A (Code Quality) score updated: 65/100 → **80/100**. Observability 20→75 (structured logging, correlation IDs, Prometheus), Security 15→40 (audit logging, sanitization), Resilience 10→35 (LLM timeouts), Spring Boot 4.x 40→70 (structured logging config). Open questions answered (public API, low traffic, LLM providers). Contrarian views resolved. Gap analysis: `.opencode/reports/gap-analysis.md`.

- 2026-06-12: **PR #140 — Production Readiness Features (MERGED)** — 11 files changed. Added: (1) Structured JSON logging via logback-spring.xml + Logstash Encoder v8.0 (CONSOLE + FILE appenders, SizeAndTimeBasedRollingPolicy 500MB/30d/10GB), (2) CorrelationFilter (OncePerRequestFilter, MDC, sanitization, UUID fallback, LLM propagation in AbstractRestLlmProvider), (3) Prometheus actuator endpoint (actuator.properties), (4) LLM RestTemplate timeouts (30s connect, 60s read using HC5 Timeout API fixing deprecated API), (5) Admin audit logging (AdminWebAdapter + LogSanitizer). Fixed 8 code review findings including 1 CRITICAL (correlation LLM propagation), 2 CodeQL (log injection, deprecated API). 6 new tests. Knowledge persisted: 3 patterns, 1 gotcha.
- 2026-06-12: **OpenCode Config Gap Fixes (Part B: 7.7/10 → 10/10)** — 7 gaps fixed across 4 files: (1) Created `.opencode/agents/observer.md` (122 lines, visual analysis spec), (2) Registered Firecrawl in superpowers-contract.json (mcp_tools + agent_to_mcp_mapping for all 10 agents), (3) Added agent_to_skill_mapping section to contract, (4) Enabled context7 for task-manager/fixer, (5) Added systematic-debugging + verification-before-completion to observer skills. Gap analysis updated in `.opencode/reports/gap-analysis.md`.

- 2026-06-12: **Codebase Analysis — COMPLETE** — PMD CPD confirms zero block-level duplication. Abstractions work. 4 remaining improvement buckets documented in Architecture Improvement Plan. Full gap analysis produced: Part A (Code Quality 65/100), Part B (OpenCode Config 7.7/10), Part C (Service Gaps 8.2/10). 20 gaps identified, prioritized into 5 CRITICAL/HIGH, 5 MEDIUM, 5 LOW, 2 MONITOR.
- 2026-06-11: **PR #134 — Dependabot Security PR Consolidation** — Consolidated 7 Dependabot PRs (GitHub Actions: checkout@v6, setup-java@v5, github-script@v9, action-gh-release@v3, action-api-scan@v0.10.0; pom.xml: Flyway 12.8.1, maven-minor-patch group) into single feature branch. Resolved 1 merge conflict in ci-publish.yml. PR #134 created.

- 2026-06-11: **PR #132 — Remaining Duplicate Code Consolidation** — Consolidated CacheConfiguration constants (UNITS_CACHE + adapter adoption in 3 adapters), normalized CategoryRepositoryAdapter buildSpecification() to accept CategoryCriteria. 5 files changed (+20/-16). 24 affected tests pass. Knowledge: 4 artifacts persisted (cache-constant-adoption-pattern, buildspecification-criteria-normalization, yagni-eventhandler-wiring, yagni-specificationhelper).
- 2026-06-10: **Cleanup & Learner Documentation** — 18 merged branches deleted, 5 stale remote refs pruned, 2 unmerged preserved. CLAUDE.md, .claude/ (6 gitnexus skill files), and docs/learning-mastery/ (46 unrelated tutorials) deleted. AGENTS.md cleaned (10 gitnexus skill refs removed). learner.md expanded (11-system post-flight matrix with governance enforcement). All 11 memory systems synced by @learner.

- 2026-06-10: **Config audit #9+#12 resolved** — Synced `SKILL.md` Envelope Shape with `template.json` (12 diff fields: scope, validation, decisions, governance, outputs, score, retry, metrics). Created `.opencode/README.md` documenting all 3 plugins (oh-my-opencode-slim, @razroo/opencode-model-fallback, superpowers) with agent wiring table. Config audit complete: 12/12 findings resolved.
- 2026-06-10: **Skills/agents updated** — 4 files: java-developer (+Generic Service Abstraction), planner (+Parallel Batch Eligibility), code-reviewer (+inherited deleteById gotcha), qa-expert (+false positive lesson). Live on disk (gitignored), auto-loaded by opencode.

- 2026-06-10: **PR #130** — Java 21 Optimization (39 files, +316/-229, 27/30 findings resolved, 859/0/0 tests)
- 2026-06-10: **PR #129** — Generic Consolidation: Shared Abstractions across 11 modules (25 files, +218/-179, 200 lines eliminated, 859/0/0 tests)

- 2026-06-05: Generic Service Phase 2 (Product, Receipt, Alert → AbstractGenericService). 7 files changed.
- 2026-06-05: PR #119 merged — Generic Service Phase 1A (Store + Price)

- 2026-06-05: PR #118 merged — Null validation standardization
- 2026-06-04: PR #117 merged — Generic repo refactoring

## Learner Analysis — PR #145 (2026-06-13)

**Bucket C: Test Pattern Dedup (Controller + Repository Adapter) — COMPLETE.** Score: 95/100.

Branch: `feature/20260613-bucket-c-test-pattern-dedup`. PR: https://github.com/RizkiRachman/goods-price-comparison-service/pull/145

- **What went well**: AbstractGenericServiceTest Template Method pattern (PR #141) successfully reapplied to 2 new test layers — WebMvcTest (setUp/ObjectMapper/MockMvc) and DataJpaTest (SpringBootTest/EntityManager). The pattern-formula is now proven across 3 test layers (service, controller, persistence).
- **What went well**: All quality gates passed first attempt — 1024 tests/0 failures, BUILD SUCCESS (Spotless, ArchUnit, SpotBugs, PMD CPD, JaCoCo). No rework needed — again. All 5 PRs in this cross-session learning (#140-#145) passed quality gates on first attempt.

- **What went well**: 23 files changed (+205/-405 = -299 lines net) — 299 lines of boilerplate removed while adding 0 new test methods. Pure structural cleanup with zero behavioral change. Validated by 1024 passing tests.
- **What went wrong**: The orchestration contract envelope was NOT updated during EXECUTE phase — it still shows cur_phase=EXECUTE with only INIT, PLAN, PLAN_SCORED completed. This violates AGENTS.md §1.6.3 (persistence after every phase change). Envelope was only written at session start, never after commits/review.

- **What went wrong**: Planner estimated ~400 lines reduction; actual was ~299 lines (75% of estimate). Overestimation due to counting boilerplate in all 19 files including test methods that weren't going to be removed. More accurate estimation: ~15 lines/file for WebMvcTest (setUp + toJson + imports) and ~6 lines/file for DataJpaTest (annotations + field).
- **What to change**: (1) Add envelope-update check to post-flight protocol — `lean-ctx ctx_knowledge remember ... orchestration-contract <updated>` after EVERY phase milestone. (2) Refine estimation for test boilerplate dedup: count actual removable lines per file, not theoretical max. (3) Extend base class pattern to save/create positive/negative test methods if 3+ services share identical behavior.

- **Knowledge persisted**: abstract-controller-web-mvc-test-base-class (architecture/pattern), abstract-repository-adapter-data-jpa-test-base-class (architecture/pattern), orchestration-envelope-stale-during-execution (gotchas/warning).
- **Envelope**: `orchestration-contract` updated with state=COMPLETE, PR #145 lessons appended.

## Learner Analysis — Testing Improvements Phase 2 (2026-06-13)

**Integration tests for all 6 remaining services — COMPLETE.** Score: 95/100 PASS.

Branch: `feature/20260613-testing-improvements-phase2`. PR: https://github.com/RizkiRachman/goods-price-comparison-service/pull/144

- **What went well**: Phase 1 pattern template made Phase 2 significantly faster — all 11 test files followed the established @SpringBootTest+@Transactional (JPA) and MockMvcBuilders.standaloneSetup() (Web) patterns. No new pattern discovery needed.
- **What went well**: Price and Receipt were the most complex services (14 + 10 JPA tests each with 7 custom queries and MultipartFile/binary data handling) — these were correctly tackled last after simpler services (ActivityLog, Alert, FeedbackQuestion, Shopping) validated the pattern.

- **What went well**: All quality gates passed on first attempt — 1024 tests, 0 failures, BUILD SUCCESS (Spotless, ArchUnit, SpotBugs, PMD CPD). No rework needed.
- **What went wrong**: Actual scope (6 services, 72 tests, 11 files) was 2.5x the contracted estimate (4 services, 29 tests, 7 files). The planner underestimated by not counting custom JPA query methods — Price has 7 custom methods, each needing 2-3 test variants.

- **What went wrong**: Test file setUp() boilerplate is 73-81% semantically similar across all 10 WebMvcTest files (Phase 1 + 2). Every file re-declares the identical Jackson2ObjectMapperBuilder configuration. This is a dedup opportunity similar to AbstractGenericServiceTest (PR #141).
- **What went wrong**: Contract envelope was not updated during Phase 2 execution — still shows state=EXECUTE_SCORED and 29 tests. The contract should be updated after each phase change, not just at start.

- **What to change**: (1) For future test planning, estimate test file complexity by counting custom JPA repository methods — each needs 2-3 test methods. (2) Extract AbstractControllerWebMvcTestBase to dedup the 10-file setUp() boilerplate (73-81% similarity). (3) Update the orchestration envelope after EVERY phase change, not just at start.
- **Knowledge persisted**: phase2-testing-pattern-datajpatest (testing/pattern), phase2-testing-pattern-webmvctest (testing/pattern), phase2-expanded-scope-deviation (testing/pattern — estimation lesson), test-setup-boilerplate-deduplication-opportunity (patterns/pattern), phase2-testing-gates-verified (architecture/pattern), springboottest-package-confusion (gotchas/info).

- **Envelope**: `orchestration-contract` updated with state=COMPLETE, PR #144 lessons appended, scope corrected from 4 to 6 services, test count corrected from 29 to 72, file count corrected from 7 to 11.

## Learner Analysis — Testing Improvements Phase 1 (2026-06-13)

**Testing: 4 core services slice tests — COMPLETE.** Score: 95/100 PASS.

Branch: `feature/20260613-testing-improvements-webmvctest-datajpatest`.

- **What went well**: Planner correctly identified Spring Boot 4.0.6 lacks @DataJpaTest/@WebMvcTest/@MockBean — adapted upfront to @SpringBootTest+@Transactional for JPA and MockMvcBuilders.standaloneSetup() for web. Saved hours of debugging.
- **What went well**: 8 files (44 tests) created in single implementation pass with only 2 minor code review findings (FQN inline, method name typo). 952 tests/0 failures, BUILD SUCCESS — remarkably clean for 1269 new lines.

- **What went wrong**: FQN inline violation (JsonNullable.of() used without import) — known convention violation (AGENTS.md §6.2). Should have been caught by implementer, not reviewer.
- **What went wrong**: `shouldEnforceUniqueName` misnamed — should be `shouldEnforceUniqueId`. Copy-paste template artifact. Low severity but indicates process gap.

- **What to change**: (1) Run `grep -n 'import.*\.'` across new files after template-based creation to catch FQN inline violations. (2) Batch-check method names match entity types after bulk file creation.
- **Knowledge persisted**: testing-improvements-phase-1-pattern (architecture/pattern), spring-boot-4.0.6-missing-slice-tests (gotchas/warning), testing-improvements-phase-1-decision (architecture/decision).

- **Envelope**: `orchestration-contract` updated with state=COMPLETE, Phase 1 lessons appended.

## Metrics

- Coverage: 91.5% INSTRUCTION / 80.6% BRANCH
- Tests: 952 passing (up from 894)

- Quality gates: ArchUnit (7 rules), SpotBugs, PMD CPD, Spotless (Google Java Style)
- Gap Analysis Part A: 80/100 (Architecture 90, Observability 75, Security 40, Resilience 35, Testing 55, Spring Boot 4.x 70)

- Gap Analysis Part B: 10/10 (all OpenCode config gaps fixed)
- Gap Analysis Part C: 10/10 — ALL BUCKETS COMPLETE (A, B, C, D, E, F)

