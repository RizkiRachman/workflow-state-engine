/**
 * Workflow State Engine — State Machine Definition
 *
 * This file encodes the canonical state machine as TypeScript symbols,
 * enabling GitNexus to index it as execution flows.
 *
 * State machine: INIT → PLAN → PLAN_SCORED → PONYTAIL_CHECK → EXECUTE → EXECUTE_SCORED → REVIEW → REVIEW_SCORED → COMPLETE
 * Any state → BLOCKED on escalation (score < 50 or max retries exhausted)
 */

// ---- State Enum ----
export const STATE_MACHINE_VERSION = "0.8.0";

export const STATES = [
  "INIT",
  "PLAN",
  "PLAN_SCORED",
  "PONYTAIL_CHECK",
  "EXECUTE",
  "EXECUTE_SCORED",
  "REVIEW",
  "REVIEW_SCORED",
  "COMPLETE",
  "BLOCKED",
] as const;

export type State = (typeof STATES)[number];

// ---- Transition Map ----
// Each entry: from → to with gate condition
export interface Transition {
  from: State;
  to: State;
  gate?: "always" | "score_ge_70" | "score_lt_50_or_retry_ge_3" | "ponytail_pass";
  description: string;
}

export const TRANSITIONS: Transition[] = [
  { from: "INIT",           to: "PLAN",           gate: "always",                     description: "Session created" },
  { from: "PLAN",           to: "PLAN_SCORED",    gate: "always",                     description: "Plan produced by system-analyst" },
  { from: "PLAN_SCORED",    to: "PONYTAIL_CHECK", gate: "score_ge_70",                description: "Plan scored ≥ 70 → ponytail gate" },
  { from: "PONYTAIL_CHECK", to: "EXECUTE",        gate: "ponytail_pass",              description: "Ponytail debt ≤ max_debt_items" },
  { from: "EXECUTE",        to: "EXECUTE_SCORED", gate: "always",                     description: "Implementation done by developer" },
  { from: "EXECUTE_SCORED", to: "REVIEW",         gate: "score_ge_70",                description: "Implementation scored ≥ 70 → review" },
  { from: "REVIEW",         to: "REVIEW_SCORED",  gate: "always",                     description: "Review done by quality-analyst" },
  { from: "REVIEW_SCORED",  to: "COMPLETE",       gate: "score_ge_70",                description: "Review scored ≥ 70 → complete" },
  // Escalation paths
  { from: "PLAN_SCORED",    to: "BLOCKED",        gate: "score_lt_50_or_retry_ge_3", description: "Plan failed to pass scoring" },
  { from: "EXECUTE_SCORED", to: "BLOCKED",        gate: "score_lt_50_or_retry_ge_3", description: "Implementation failed scoring" },
  { from: "REVIEW_SCORED",  to: "BLOCKED",        gate: "score_lt_50_or_retry_ge_3", description: "Review failed scoring" },
  { from: "PONYTAIL_CHECK", to: "BLOCKED",        gate: "score_lt_50_or_retry_ge_3", description: "Ponytail debt threshold exceeded" },
];

// ---- Forward Flow Path ----
// The happy path through the state machine
export const FORWARD_FLOW: State[] = [
  "INIT",
  "PLAN",
  "PLAN_SCORED",
  "PONYTAIL_CHECK",
  "EXECUTE",
  "EXECUTE_SCORED",
  "REVIEW",
  "REVIEW_SCORED",
  "COMPLETE",
];

// ---- Transition Validator ----
export function isValidTransition(from: State, to: State): boolean {
  return TRANSITIONS.some((t) => t.from === from && t.to === to);
}

export function getTransition(from: State): Transition[] {
  return TRANSITIONS.filter((t) => t.from === from);
}

// ---- Orchestrator Function ----
// Entry point for state machine orchestration.
// GitNexus detects this as an execution flow process.

export interface OrchestrationContext {
  currentState: State;
  score: { combined: number };
  retry: { attempt: number };
  ponytail: { debt_items: unknown[] };
}

function checkScoreGate(score: number): boolean {
  return score >= 70;
}

function checkEscalation(score: number, attempt: number): boolean {
  return score < 50 || attempt >= 3;
}

function checkPonytailGate(debtItems: unknown[]): boolean {
  return debtItems.length <= 10;
}

export function orchestrateTransition(ctx: OrchestrationContext): State {
  const { currentState, score, retry, ponytail } = ctx;

  // Forward transitions
  if (currentState === "INIT") return "PLAN";
  if (currentState === "PLAN") return "PLAN_SCORED";

  // Plan scoring gate
  if (currentState === "PLAN_SCORED") {
    if (checkEscalation(score.combined, retry.attempt)) return "BLOCKED";
    if (checkScoreGate(score.combined)) return "PONYTAIL_CHECK";
    return "BLOCKED";
  }

  // Ponytail gate
  if (currentState === "PONYTAIL_CHECK") {
    if (checkPonytailGate(ponytail.debt_items)) return "EXECUTE";
    return "BLOCKED";
  }

  if (currentState === "EXECUTE") return "EXECUTE_SCORED";

  // Execute scoring gate
  if (currentState === "EXECUTE_SCORED") {
    if (checkEscalation(score.combined, retry.attempt)) return "BLOCKED";
    if (checkScoreGate(score.combined)) return "REVIEW";
    return "BLOCKED";
  }

  if (currentState === "REVIEW") return "REVIEW_SCORED";

  // Review scoring gate
  if (currentState === "REVIEW_SCORED") {
    if (checkEscalation(score.combined, retry.attempt)) return "BLOCKED";
    if (checkScoreGate(score.combined)) return "COMPLETE";
    return "BLOCKED";
  }

  // Terminal states
  if (currentState === "COMPLETE") return "COMPLETE";
  if (currentState === "BLOCKED") return "BLOCKED";

  return "BLOCKED";
}

