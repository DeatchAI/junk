import type { DemoMessage, DemoRun, DemoTranscriptPart } from "./demo-data";

const prompts = [
  "Can you investigate why the expanded composer sometimes opens too small?",
  "Does it happen when an older conversation finishes loading?",
  "Check how the window calculates its initial height.",
  "Could AppKit be applying an outdated fitting size?",
  "Please trace the resize sequence before changing anything.",
  "Keep the current compact composer behavior unchanged.",
  "Fix the expanded layout and add a focused regression check.",
  "Run the build and summarize the changes and any remaining checks.",
];

const earlierAnswers = [
  "I’ll trace the composer window’s sizing and reproduce the expansion path.",
  "The timing matters: conversation content can arrive after the window begins expanding.",
  "The initial height comes from the panel frame, but a later fitting pass can replace it.",
  "Yes. A fitting measurement may arrive before the expanded bounds are ready.",
  "I’ll follow the window resize and content-fit callbacks together.",
  "I’ll scope the change to expanded mode and preserve the compact sizing path.",
  "I’ve adjusted the expanded height and added coverage for delayed content.",
];

const finalTranscript: DemoTranscriptPart[] = [
  { kind: "activity", summary: "Read files, ran commands", details: ["Inspected the composer window and expansion controls", "Traced the content-fit and resize callbacks"] },
  { kind: "text", text: "I found a sizing race: just after expanding, the app could use stale view bounds as the expanded height. I changed it to use the panel’s target frame and kept later fitting updates from shrinking the expanded view." },
  { kind: "activity", summary: "Ran 3 commands", details: ["Built the macOS app", "Ran the focused composer checks", "Checked the source diff"] },
  { kind: "text", text: "The build and focused checks passed. Compact mode keeps its existing sizing behavior. The live expand button still needs a manual check in the installed app." },
];

export const featureMessages: DemoMessage[] = prompts.map((prompt, index) => ({
  id: `feature-message-${index + 1}`,
  prompt,
  files: [],
  agent: "codex",
  answer: index === prompts.length - 1
    ? finalTranscript.filter(part => part.kind === "text").map(part => part.text).join("\n\n")
    : earlierAnswers[index],
  ...(index === prompts.length - 1 ? { transcript: finalTranscript } : {}),
}));

export const featureRuns: DemoRun[] = [
  {
    id: "feature-approval", title: "Fix the Mac app build", agent: "claude", project: "Detach",
    conversationId: "feature-approval", messageId: "approval-message", state: "approval", activity: "Approval needed",
    attention: { kind: "approval", prompt: "Push the verified release branch to the remote repository?",
      command: "git push origin release/mac-app", risk: "High-risk action" },
  },
  {
    id: "feature-question", title: "Review the release changes", agent: "codex", project: "Detach",
    conversationId: "feature-question", messageId: "question-message", state: "question", activity: "Needs your answer",
    attention: { kind: "question", prompt: "Which part should I review first?", options: [
      { label: "Mac app", description: "Check the native interface and task lifecycle" },
      { label: "Runtime", description: "Check provider adapters and permission handling" },
    ] },
  },
  {
    id: "feature-running", title: "Review the project structure", agent: "pi", project: "Detach",
    conversationId: "feature-running", messageId: "running-message", state: "running", activity: "Reading the source files",
  },
];
