import { type ServerWebSocket, history, nativeHistory, agents, savedWorkflows, slashCommands, composio, browserAutomation, desktopBridge, capabilityBroker, agentQuestions, activeRuns } from "./RuntimeContext";
import { type ChatRequest } from "../protocol/messages";
import { matchDemoScenario, createDemoRun } from "../demo/DemoScenarios";
import { learnedActionSkillAttachment } from "../actions/ActionSkillManager";
import { normalizeBrowserTabAttachments, browserTabSystemInstruction } from "../browser/BrowserTabContext";
import { uniqueStrings, send, sendBrowserActivity, estimateTokenCount, mergeSystemInstructions } from "./RuntimeHelpers";
import { resolveConversationMCPServerIds, buildAgentMCPServers } from "./RuntimeTools";
import { CAPABILITY_BROKER_ID } from "../capabilities/CapabilityConstants";
import { composerModeSystemInstruction } from "../composer/composerModes";
import { resolveSelectedSkillInstructions } from "../skills/SkillResolver";
import { isWaitingForAnswer } from "../questions/QuestionWait";
import { normalizeAgentActivity } from "../activity/ActivityNormalizer";
import { requestAgentPermission } from "./RuntimeApprovals";
import { NativeRunContext } from "../history/native/NativeRunContext";
import { ResponseTranscript } from "../activity/ResponseTranscript";
import { chatContextSummary } from "./ChatContextSummary";

export async function handleChat(ws: ServerWebSocket, input: ChatRequest) {
  if (activeRuns.has(ws)) throw new Error("This connection already has an active task.");
  const storedText = input.displayText?.trim() || input.text || "";
  const demo = !input.branchFrom ? matchDemoScenario(storedText, input.demoMode === true) : undefined;
  const stored = input.conversationId ? nativeHistory.index.get(input.conversationId)?.conversation
    ?? history.get(input.conversationId)?.conversation : undefined;
  const provider = agents.get(input.agent ?? stored?.provider).id;
  const frame = await NativeRunContext.prepare(nativeHistory, history,
    demo ? { ...input, conversationId: undefined } : input, provider, input.runId ?? crypto.randomUUID());
  const message: ChatRequest = { ...input, agent: provider, workspacePath: frame.workspacePath,
    providerSessionId: frame.resumeSessionID, providerSessionPath: frame.nativeSessionPath, providerFork: frame.forkPoint };
  if (demo) frame.conversation.id = `demo_${frame.runID}`;
  try { await runChat(ws, message, frame, demo); }
  finally {
    await frame.release();
    const id = frame.bound ? frame.conversation.id : input.conversationId;
    if (id && nativeHistory.index.source(id)) send(ws, nativeHistory.index.branchState(id));
  }
}

async function runChat(ws: ServerWebSocket, message: ChatRequest, frame: NativeRunContext, demo: ReturnType<typeof matchDemoScenario>) {
  const startTime = Date.now(); const runId = frame.runID;
  const agent = agents.get(frame.provider); const conversation = frame.conversation;
  const publicID = () => frame.bound || frame.nativeSessionID || demo ? conversation.id : undefined;
  const action = message.actionId ? savedWorkflows.get(message.actionId) : undefined;
  if (message.actionId && action?.kind !== "workflow") throw new Error("This workflow is unavailable. Quick Actions have been removed.");
  const slashCommand = message.slashCommandId ? slashCommands.get(message.slashCommandId) : undefined;
  const learnedSkill = action ? learnedActionSkillAttachment(action) : undefined;
  const attachedBrowserTabs = normalizeBrowserTabAttachments(message.browserTabs);
  const requestSkills = learnedSkill ? [learnedSkill, ...(message.skills ?? [])] : message.skills;
  const requestedIDs = attachedBrowserTabs.length ? uniqueStrings([...(message.mcpServerIds ?? []), "detach-browser-tools"]) : message.mcpServerIds;
  const mcpIDs = resolveConversationMCPServerIds(conversation.id, requestedIDs, Boolean(message.runId));
  await composio.refreshAccess();
  const agentMCPServers = buildAgentMCPServers(mcpIDs, runId);
  const brokerActive = agentMCPServers.some((server) => server.enabled && server.id === CAPABILITY_BROKER_ID);
  let browserActive = mcpIDs?.includes("detach-browser-tools") ?? false;
  let fullText = ""; let firstChunkAt: number | undefined;
  const transcript = new ResponseTranscript();
  const activity = (subtitle: string) => send(ws, { type: "activity", runId, conversationId: publicID(),
    activityStatus: `Using ${agent.displayName}`, event: { agent: agent.id, kind: "lifecycle", action: "prepare", phase: "started",
      title: `${agent.displayName} is working`, subtitle, userFacing: true } });
  activity("Preparing your task");

  try {
    if (browserActive) {
      await browserAutomation.beginTask(runId, [frame.workspacePath, ...(message.files?.map((file) => file.path) ?? [])],
        (event) => sendBrowserActivity(ws, runId, publicID(), agent.id, event));
    }
    if (brokerActive) capabilityBroker.registerRun(runId, { allowedUploadPaths: [frame.workspacePath, ...(message.files?.map((file) => file.path) ?? [])],
      activitySink: (event) => sendBrowserActivity(ws, runId, publicID(), agent.id, event) });
    const request: ChatRequest = { ...message, runId, skills: requestSkills, mcpServerIds: mcpIDs,
      conversationId: conversation.id, contextMessages: frame.contextMessages, mcpServers: agentMCPServers,
      systemPrompt: mergeSystemInstructions(message.systemPrompt,
        composerModeSystemInstruction(message.composerMode ?? slashCommand?.mode), slashCommand?.promptInstruction,
        resolveSelectedSkillInstructions(requestSkills)),
      attachmentContext: mergeSystemInstructions(message.attachmentContext, browserTabSystemInstruction(attachedBrowserTabs)),
      browserTabs: attachedBrowserTabs.length ? attachedBrowserTabs : undefined };
    send(ws, { type: "context_summary", contextSummary: chatContextSummary(request) });
    agentQuestions.registerRun(runId, { ws, conversationId: conversation.id, agent: agent.id, taskTitle: conversation.title });
    const callbacks = {
      onSession(session) {
        frame.bind(session);
        if (mcpIDs?.length) nativeHistory.index.rememberMCPs(conversation.id, mcpIDs);
        agentQuestions.bindConversation(runId, conversation.id, conversation.title);
        activity("Connected to the provider's saved session");
        send(ws, { type: "provider_session", runId, conversation: nativeHistory.index.get(conversation.id)!.conversation });
        send(ws, nativeHistory.index.branchState(conversation.id));
      },
      onTitle(title: string) {
        if (!frame.bound) return;
        conversation.title = title; nativeHistory.updateTitle(conversation.id, title);
        send(ws, { type: "conversation_title", conversationId: conversation.id, title });
      },
      onActivity(status, toolName, event) {
        if (isWaitingForAnswer(runId)) return;
        const normalized = normalizeAgentActivity(agent.id, status, toolName, event);
        transcript.activity(normalized);
        if (normalized.userFacing) send(ws, { type: "activity", runId, conversationId: publicID(),
          activityStatus: normalized.title, toolName, event: normalized });
      },
      onChunk(text: string) {
        transcript.text(text);
        if (!firstChunkAt) {
          firstChunkAt = Date.now(); send(ws, { type: "chunk", text, isFirst: true, timeToFirstChunkMs: firstChunkAt - startTime });
        } else send(ws, { type: "chunk", text });
        fullText += text;
      },
      onPermission(permission) { return requestAgentPermission(ws, permission, runId, conversation.id); },
      onQuestion(question) { return agentQuestions.ask(runId, question); },
    } satisfies Parameters<typeof agent.run>[1];
    desktopBridge.registerRun(runId);
    const run = demo ? createDemoRun(demo, agent.id, callbacks) : agent.run(request, callbacks);
    const desktopAwareRun = { ...run, cancel() { desktopBridge.endRun(runId); run.cancel(); } };
    desktopBridge.registerRun(runId, () => run.cancel());
    activeRuns.set(ws, desktopAwareRun);
    const result = await run.finished;
    if (!fullText && result.text) { fullText = result.text; transcript.text(result.text); }
    if (!frame.bound && !demo) throw new Error(`${agent.displayName} did not acknowledge a saved session. No Detach-only conversation was created.`);
    transcript.finish();
    frame.cacheResponse(fullText, transcript.parts);
    if (brokerActive) await capabilityBroker.endRun(runId);
    if (browserActive) { await browserAutomation.endTask(runId); browserActive = false; }
    if (action) savedWorkflows.update(action.id, { lastSuccessfulRunAt: Date.now() });
    send(ws, { type: "done", runId, conversationId: conversation.id, tokenCount: estimateTokenCount(fullText), durationMs: Date.now() - startTime });
  } catch (error) {
    transcript.finish();
    frame.cacheResponse(fullText, transcript.parts);
    send(ws, { type: "error", error: error instanceof Error ? error.message : String(error), runId });
    if (frame.bound || demo) send(ws, { type: "done", runId, conversationId: conversation.id,
      tokenCount: estimateTokenCount(fullText), durationMs: Date.now() - startTime });
  } finally {
    desktopBridge.endRun(runId);
    agentQuestions.endRun(runId);
    if (brokerActive) await capabilityBroker.endRun(runId).catch(() => undefined);
    if (browserActive) await browserAutomation.endTask(runId).catch(() => undefined);
    activeRuns.delete(ws);
  }
}
