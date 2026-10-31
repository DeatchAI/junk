/** Shared human-wait accounting for both questions and permission approvals. */
const waitingRuns = new Map<string, { count: number; startedAt: number; elapsed: number }>();

export function beginQuestionWait(runId: string) {
  const state = waitingRuns.get(runId) ?? { count: 0, startedAt: Date.now(), elapsed: 0 };
  if (state.count === 0) state.startedAt = Date.now();
  state.count++;
  waitingRuns.set(runId, state);
  let finished = false;
  return () => {
    if (finished) return;
    finished = true;
    state.count--;
    if (state.count === 0) state.elapsed += Date.now() - state.startedAt;
  };
}

export function isWaitingForAnswer(runId?: string) {
  return Boolean(runId && (waitingRuns.get(runId)?.count ?? 0) > 0);
}

export function questionWaitMs(runId?: string) {
  const state = runId ? waitingRuns.get(runId) : undefined;
  return state ? state.elapsed + (state.count > 0 ? Date.now() - state.startedAt : 0) : 0;
}

export function clearQuestionWait(runId: string) { waitingRuns.delete(runId); }
