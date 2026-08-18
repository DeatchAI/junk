import type { AgentRun, AgentStreamCallbacks } from "../agents/AgentAdapter";
import type { AgentActivityEvent, AgentActivityKind, AgentKind } from "../protocol/messages";

export const DEMO_TRIGGER_PROMPTS = {
  developer: "Review the attached checkout pull request, test changes, and CI notes for bugs, regressions, and missing tests.",
  hiring: "Fix the failing tests in the attached project files, run the relevant checks, and show me the diff.",
  operations: "Open the staging checkout URL from the attached runbook, reproduce the payment bug, and tell me what broke.",
  research: "Use the attached pricing brief to compare the current plans for these tools and cite the live sources.",
  sales: "Review the attached Downloads folder and propose a cleaner project-based organization without deleting anything.",
  coding: "Build a small dashboard from the attached usage CSV and run it locally.",
  paystubs: "Log in to the admin dashboard and export this month's usage report using the attached report specification.",
  xReplies: "Summarize the attached meeting transcript and turn the action items into a checklist.",
} as const;

type DemoScenarioId = keyof typeof DEMO_TRIGGER_PROMPTS;

interface DemoActivityStep {
  type: "activity";
  delayMs: number;
  status: string;
  title: string;
  subtitle?: string;
  toolName?: string;
  kind: AgentActivityKind;
}

interface DemoChunkStep {
  type: "chunk";
  delayMs: number;
  text: string;
}

type DemoStep = DemoActivityStep | DemoChunkStep;

// Demo recordings need enough dwell time for the activity lane and the notch to
// be readable. Real agents also spend longer between visible state changes than
// between streamed text chunks.
const ACTIVITY_PACING_MULTIPLIER = 2.6;
const MIN_CHUNK_PACING_MS = 700;

const DEMO_CAPABILITIES: Record<DemoScenarioId, string[]> = {
  developer: [],
  hiring: [],
  operations: ["Browser"],
  research: ["Browser"],
  sales: ["macOS"],
  coding: [],
  paystubs: ["Browser", "Secrets"],
  xReplies: [],
};

export interface DemoScenario {
  id: DemoScenarioId;
  prompt: string;
  openingText: string;
  progressText: string;
  steps: DemoStep[];
}

const scenarios: Record<DemoScenarioId, DemoScenario> = {
  developer: {
    id: "developer",
    prompt: DEMO_TRIGGER_PROMPTS.developer,
    openingText: "I’ll inspect the pull request, read the changed files and test history, then check the risky paths before I write a review with concrete findings.\n\n",
    progressText: "The main risk is in the checkout state transition. I’m comparing the new branch with the last passing commit and checking whether the existing tests cover the failure path.\n\n",
    steps: [
      activity(1400, "Opening the attached pull request files", "Reviewing pull request", "Checkout change set · 12 changed files", "files.read"),
      activity(1700, "Reading the checkout and payment tests", "Checking test coverage", "Retry, timeout, and success paths", "files.read", "mcp_tool"),
      activity(1600, "Comparing the attached changes with the last green build", "Comparing recent builds", "Build #1842 versus #1837", "git.diff"),
      activity(1500, "Tracing the risky checkout state transition", "Checking regression path", "Payment can remain pending after a timeout", "files.read"),
      activity(1200, "Drafting review findings with file references", "Preparing review comments", "Nothing will be posted", "files.write", "file_change"),
      chunk(350, "I reviewed the pull request and found two actionable issues.\n\n"),
      chunk(250, "**Review findings**\n\n- The retry path can leave checkout stuck in `pending` when the payment iframe times out.\n- The error branch drops the original request ID, which makes support replay harder.\n- Existing tests cover the happy path but not a timeout followed by retry.\n\n"),
      chunk(200, "I prepared precise file and test references for the review. Nothing was posted or changed."),
    ],
  },
  hiring: {
    id: "hiring",
    prompt: DEMO_TRIGGER_PROMPTS.hiring,
    openingText: "I’ll reproduce the failing tests, trace the first broken assertion, make the smallest safe fix, and run the relevant checks before I show you the diff.\n\n",
    progressText: "The failures point to one changed date-handling helper rather than the three separate test cases. I’m checking its callers now so the fix does not hide a real regression.\n\n",
    steps: [
      activity(1400, "Opening the project and reproducing the failures", "Running the failing test suite", "7 failures · date-formatting.test.ts", "bun test", "command"),
      activity(1600, "Tracing the first broken assertion", "Reading the failure path", "Timezone offset changes the expected date", "files.read", "mcp_tool"),
      activity(1700, "Checking every caller of the date helper", "Inspecting related code", "Invoice, export, and notification paths", "files.read", "mcp_tool"),
      activity(1500, "Applying the smallest compatible fix", "Updating the date helper", "Preserving the existing UTC contract", "files.write", "file_change"),
      activity(1200, "Running focused tests and the type check", "Verifying the fix", "Focused tests pass · type check passes", "bun test", "command"),
      chunk(350, "I fixed the shared date helper and reran the affected checks.\n\n"),
      chunk(250, "**Verification**\n\n- 7 failing tests now pass\n- The UTC contract is explicit at the helper boundary\n- Invoice export and notification callers keep their existing behavior\n- Type checking passes\n\n"),
      chunk(200, "The diff is limited to the helper and its regression tests. I did not commit or push anything."),
    ],
  },
  operations: {
    id: "operations",
    prompt: DEMO_TRIGGER_PROMPTS.operations,
    openingText: "I’ll open staging, reproduce the checkout issue in the browser, capture the failing step and console state, then compare it with the last known-good deployment.\n\n",
    progressText: "The bug reproduces only after a failed payment attempt. I’m checking the browser state and deployment configuration together so I can separate a frontend regression from an environment problem.\n\n",
    steps: [
      activity(1400, "Opening the staging checkout", "Navigating staging", "Checkout · Chrome tab 3", "browser.open"),
      activity(1700, "Reproducing the failed payment path", "Replaying checkout", "Payment succeeds, redirect never completes", "browser.interact"),
      activity(1600, "Inspecting console and network state", "Reading browser diagnostics", "Order status remains `pending`", "browser.inspect"),
      activity(1500, "Comparing the last good deployment", "Comparing deployments", "Environment variable changed in release 2026.08.14", "browser.open"),
      activity(1200, "Preparing a reproducible bug report", "Writing reproduction steps", "No staging data will be changed", "files.write", "file_change"),
      chunk(350, "I reproduced the checkout bug consistently after a failed payment attempt.\n\n"),
      chunk(250, "**What broke**\n\n- The payment provider returns success, but the redirect listener is not reattached after the retry.\n- The order stays in `pending`, so the confirmation page waits forever.\n- The last good deployment included the listener initialization; the current release moved it behind a client-only branch.\n\n"),
      chunk(200, "I captured the exact reproduction steps and the relevant console state. I did not place an order or change staging."),
    ],
  },
  research: {
    id: "research",
    prompt: DEMO_TRIGGER_PROMPTS.research,
    openingText: "I’ll check the current pricing pages for each tool, record the plan limits and billing terms, and build a comparison with source links and access dates.\n\n",
    progressText: "The headline prices are easy to compare, but the usage limits and annual billing rules differ. I’m checking the plan details and keeping those caveats beside each number.\n\n",
    steps: [
      activity(1400, "Opening the current pricing pages", "Collecting pricing evidence", "4 tools · official plan pages", "browser.open"),
      activity(1700, "Capturing plan limits and billing terms", "Reading plan details", "Seats, usage, annual discount, API access", "browser.snapshot"),
      activity(1600, "Comparing equivalent plans", "Normalizing the comparison", "Monthly price versus included usage", "browser.open"),
      activity(1500, "Checking pricing footnotes and exclusions", "Reviewing caveats", "Two features require annual billing", "browser.snapshot"),
      activity(1200, "Building the source-backed comparison", "Preparing pricing table", "Source URLs and access dates included", "files.write", "file_change"),
      chunk(350, "I checked the current official pricing pages and built the comparison.\n\n"),
      chunk(250, "**Pricing snapshot**\n\n- Tool A has the lowest monthly entry price, but usage overages start sooner.\n- Tool B includes the strongest team permissions on its first paid plan.\n- Tool C is cheaper annually but does not include API access at the starter tier.\n- Tool D has the clearest usage-based pricing, with no annual commitment required.\n\n"),
      chunk(200, "The table includes source links, access dates, plan limits, and the billing caveats. I did not start a trial or enter payment details."),
    ],
  },
  sales: {
    id: "sales",
    prompt: DEMO_TRIGGER_PROMPTS.sales,
    openingText: "I’ll inspect the files in Downloads, group them by project and file type, and prepare a proposed move list for you to review before anything changes on disk.\n\n",
    progressText: "Most files map cleanly to three projects. I found a few ambiguous exports and duplicates, so I’m leaving those in place instead of guessing where they belong.\n\n",
    steps: [
      activity(1400, "Scanning the Downloads folder", "Reading local file inventory", "42 files · 6 folders", "detach_macos_snapshot", "mcp_tool"),
      activity(1700, "Grouping files by project and type", "Organizing file candidates", "Invoices, exports, screenshots, and notes", "files.read", "mcp_tool"),
      activity(1600, "Finding duplicates and ambiguous files", "Checking proposed moves", "8 duplicates · 4 files need your choice", "detach_macos_snapshot", "mcp_tool"),
      activity(1500, "Preparing a reviewable move list", "Drafting file plan", "No files will move automatically", "files.write", "file_change"),
      activity(1200, "Checking the proposed folder structure", "Reviewing organization plan", "Project folders stay inside Downloads", "detach_macos_snapshot", "mcp_tool"),
      chunk(350, "I organized the Downloads inventory into a reviewable move plan.\n\n"),
      chunk(250, "**Proposed structure**\n\n- `Acme/` — briefs, screenshots, and exported reports\n- `Detach/` — product notes, test captures, and release files\n- `Personal/` — receipts and travel documents\n- `Needs review/` — 4 ambiguous files and 8 duplicate candidates\n\n"),
      chunk(200, "Nothing was moved or deleted. The plan leaves ambiguous files in place until you approve the changes."),
    ],
  },
  coding: {
    id: "coding",
    prompt: DEMO_TRIGGER_PROMPTS.coding,
    openingText: "I’ll inspect the CSV columns and the existing app structure, then build a small dashboard with useful filters, a clear summary view, and an interactive detail panel.\n\n",
    progressText: "The CSV has three useful dimensions and one inconsistent date field. I’ve normalized that field and I’m checking loading, empty, and no-match states before the local run.\n\n",
    steps: [
      activity(1400, "Inspecting the CSV and project structure", "Reading project context", "Finding columns, entry points, and existing styles", "files.read", "mcp_tool"),
      activity(1700, "Planning the dashboard information hierarchy", "Designing the dashboard", "Summary, filters, chart, and detail views", "planning", "plan"),
      activity(1600, "Normalizing the CSV for interaction", "Preparing dashboard data", "Dates, categories, totals, and missing values", "files.read", "mcp_tool"),
      activity(1500, "Building the dashboard layout and filters", "Implementing dashboard UI", "Interactive segments and empty states", "files.write", "file_change"),
      activity(1300, "Adding the chart and detail panel", "Adding interactive insights", "Keep the row-level data beside each summary", "files.write", "file_change"),
      activity(1400, "Running the local build", "Checking dashboard build", "Verifying the primary interaction flow", "npm run build", "command"),
      chunk(350, "The CSV dashboard is ready for review.\n\n"),
      chunk(250, "**What it includes**\n\n- A filterable table with the original row context\n- A summary chart for the strongest categories\n- A detail panel that keeps the source values beside each conclusion\n- Clear loading, empty, and no-match states\n\n"),
      chunk(200, "The local build completed successfully. I left the source CSV unchanged and did not publish the dashboard."),
    ],
  },
  paystubs: {
    id: "paystubs",
    prompt: DEMO_TRIGGER_PROMPTS.paystubs,
    openingText: "I’ll open the admin dashboard, use the saved sign-in only through the secure on-device flow, and prepare this month’s usage export for your review. I’ll stop before any real download or account change.\n\n",
    progressText: "The dashboard is open and the secure credential handoff is complete. I found the current reporting period and I’m checking the export filters before I prepare the result.\n\n",
    steps: [
      activity(1400, "Opening the admin dashboard", "Navigating to usage reports", "Reports · current workspace", "browser.open"),
      activity(1500, "Finding the saved dashboard credential", "Looking up saved credential", "Only masked metadata is available to the agent", "secrets.search", "mcp_tool"),
      activity(1700, "Requesting on-device credential approval", "Waiting for Touch ID", "Secure sign-in requires your confirmation", "Touch ID", "status"),
      activity(1500, "Signing in without exposing the credential", "Filling credential securely", "Credential is filled directly in the browser", "secrets.use_browser", "mcp_tool"),
      activity(1600, "Selecting this month's usage filters", "Preparing usage export", "Checking workspace, date range, and CSV format", "browser.snapshot"),
      activity(1300, "Preparing the export summary", "Staging usage report", "No real file will be downloaded", "files.write", "file_change"),
      chunk(350, "I prepared the usage export settings for this month.\n\n"),
      chunk(250, "**Export ready for review**\n\n- Workspace: Acme production\n- Period: August 1–14, 2026\n- Format: CSV\n- Included: active users, runs, tool calls, and estimated credits\n\n"),
      chunk(200, "The credential was never exposed in the chat or activity log. This demo did not access a real dashboard or download a real report."),
    ],
  },
  xReplies: {
    id: "xReplies",
    prompt: DEMO_TRIGGER_PROMPTS.xReplies,
    openingText: "I’ll read the meeting transcript, separate decisions from open questions, and turn the actionable items into a checklist with owners and due dates where the transcript provides them.\n\n",
    progressText: "The transcript has four clear decisions and several follow-ups. I’m separating confirmed owners from suggestions so the checklist does not invent accountability.\n\n",
    steps: [
      activity(1400, "Opening the meeting transcript", "Reading meeting notes", "Product planning · 58 minutes", "files.read", "mcp_tool"),
      activity(1600, "Extracting decisions and open questions", "Structuring the discussion", "Decisions, risks, owners, and follow-ups", "planning", "plan"),
      activity(1700, "Matching action items to named owners", "Checking accountability", "Only explicit owners are included", "files.read", "mcp_tool"),
      activity(1500, "Drafting the follow-up checklist", "Preparing action items", "Due dates remain blank where none were agreed", "files.write", "file_change"),
      activity(1300, "Reviewing the summary for omissions", "Checking meeting summary", "Decisions remain separate from suggestions", "files.read", "mcp_tool"),
      chunk(350, "I summarized the meeting and prepared the follow-up checklist.\n\n"),
      chunk(250, "**Summary**\n\n- The team approved the new onboarding flow for the next release.\n- Analytics instrumentation is required before rollout.\n- Support needs a migration note and a short FAQ.\n- The launch date remains open pending the analytics check.\n\n**Action items**\n- Priya — add the analytics events.\n- Mateo — draft the migration note.\n- Unassigned — confirm the launch date after the analytics check.\n\n"),
      chunk(200, "I kept unassigned work visible instead of guessing an owner. The transcript file was not changed."),
    ],
  },
};

const DEMO_COMPOSER_TOKENS = new Set([
  "@Browser",
  "@macOS",
  "@Secrets",
  "/code-review",
  "/debug",
  "/plan",
  "/compact-context",
  "@checkout-review",
  "@checkout-pr.patch",
  "@checkout-payment-test.ts",
  "@ci-notes.md",
  "@test-fix-project",
  "@date-formatting-test.ts",
  "@staging-checkout.md",
  "@pricing-brief.md",
  "@downloads-demo",
  "@acme-invoice.csv",
  "@detach-release-notes.md",
  "@usage-dashboard",
  "@usage.csv",
  "@report-spec.md",
  "@meeting-transcript.md",
]);

export function normalizeDemoPrompt(prompt: string): string {
  return prompt
    .split(/\s+/)
    .filter((token) => token.length > 0 && !DEMO_COMPOSER_TOKENS.has(token))
    .join(" ")
    .trim();
}

export function matchDemoScenario(prompt: string, enabled: boolean): DemoScenario | undefined {
  if (!enabled) return undefined;
  const normalized = normalizeDemoPrompt(prompt.replace(/\r\n/g, "\n"));
  return Object.values(scenarios).find((scenario) => scenario.prompt === normalized);
}

export function createDemoRun(
  scenario: DemoScenario,
  agent: AgentKind,
  callbacks: AgentStreamCallbacks,
  wait: (milliseconds: number) => Promise<void> = sleep
): AgentRun {
  let cancelled = false;
  const steps: DemoStep[] = [
    activity(1600, "Understanding the request and planning the run", "Planning the task", "Breaking the request into reviewable steps", undefined, "plan"),
    chunk(850, scenario.openingText),
    activity(1400, "Checking workspace memory for relevant context", "Checking workspace memory", "Looking for prior instructions and saved context", "workspace.memory", "status"),
    toolAccessStep(scenario),
    ...scenario.steps.flatMap((step, index) =>
      index === 3 ? [chunk(650, scenario.progressText), step] : [step]
    ),
  ];

  return {
    cancel() {
      cancelled = true;
    },
    finished: (async () => {
      let text = "";
      for (const step of steps) {
        await wait(step.delayMs);
        if (cancelled) throw new Error("Demo stopped");

        if (step.type === "chunk") {
          text += step.text;
          callbacks.onChunk(step.text);
          continue;
        }

        const event: AgentActivityEvent = {
          id: `demo_${scenario.id}_${crypto.randomUUID()}`,
          agent,
          kind: step.kind,
          phase: "started",
          title: step.title,
          subtitle: step.subtitle,
          toolName: step.toolName,
          userFacing: true,
          sourceEventType: "detach.demo",
          sourceItemType: scenario.id,
          details: { demo: true },
        };
        callbacks.onActivity(step.status, step.toolName, event);
      }
      return { text };
    })(),
  };
}

function activity(
  delayMs: number,
  status: string,
  title: string,
  subtitle: string,
  toolName?: string,
  kind: AgentActivityKind = "mcp_tool"
): DemoActivityStep {
  return {
    type: "activity",
    delayMs: Math.round(delayMs * ACTIVITY_PACING_MULTIPLIER),
    status,
    title,
    subtitle,
    toolName,
    kind,
  };
}

function chunk(delayMs: number, text: string): DemoChunkStep {
  return { type: "chunk", delayMs: Math.max(MIN_CHUNK_PACING_MS, delayMs * 2), text };
}

function toolAccessStep(scenario: DemoScenario): DemoActivityStep {
  const capabilities = DEMO_CAPABILITIES[scenario.id];
  if (capabilities.length === 0) {
    return activity(
      1200,
      "Reviewing attached files and workspace context",
      "Checking attached context",
      "No external capabilities selected",
      "files.read",
      "status"
    );
  }

  return activity(
    1200,
    `Reviewing ${capabilities.join(" and ")} access`,
    "Checking requested capabilities",
    `${capabilities.join(" · ")} selected for this task`,
    "MCP registry",
    "mcp_tool"
  );
}

function sleep(milliseconds: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
}
