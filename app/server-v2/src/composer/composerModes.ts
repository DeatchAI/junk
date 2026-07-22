export type ComposerMode = "explain_only" | "plan_only" | "review_only" | "debug_only";

export function composerModeSystemInstruction(mode?: ComposerMode): string | undefined {
  switch (mode) {
    case "explain_only":
      return [
        "The user invoked explain-only mode.",
        "Explain how things work clearly.",
        "Do not suggest edits, refactors, file changes, or code changes unless the user explicitly asks.",
      ].join(" ");
    case "plan_only":
      return [
        "The user invoked plan-only mode.",
        "Produce a concise implementation plan before making changes.",
        "Do not write or apply code yet unless the user explicitly asks.",
      ].join(" ");
    case "review_only":
      return [
        "The user invoked review-only mode.",
        "Review for bugs, regressions, risks, and missing tests.",
        "Do not rewrite code unless a small example is necessary to explain a finding.",
      ].join(" ");
    case "debug_only":
      return [
        "The user invoked debug-only mode.",
        "Diagnose the issue step by step and identify the most likely root cause.",
        "Do not implement a fix until the user explicitly asks.",
      ].join(" ");
    default:
      return undefined;
  }
}
