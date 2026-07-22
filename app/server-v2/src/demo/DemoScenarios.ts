import type { AgentRun, AgentStreamCallbacks } from "../agents/AgentAdapter";
import type { AgentActivityEvent, AgentActivityKind, AgentKind } from "../protocol/messages";

export const DEMO_TRIGGER_PROMPTS = {
  developer: "Triage the failed CI run for this PR and draft a review note with evidence.",
  hiring: "Check onboarding readiness for our new hire starting Monday.",
  operations: "Review our top five SaaS renewals and flag anything that needs attention.",
  research: "Verify the claims in this market brief against the current sources.",
  sales: "Prepare a source-backed brief for my Acme discovery call.",
  coding: "Build a dashboard to make our research findings interactive.",
  paystubs: "Get my paystubs for this month.",
  xReplies: "Reply to all comments my X post has received.",
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
    openingText: "I’ll go through the PR, inspect the failed CI run, and compare it with the last passing build before I draft the review note.\n\n",
    progressText: "I’ve isolated the failure to the mobile checkout job. I’m opening the trace now to confirm whether the environment change is the cause.\n\n",
    steps: [
      activity(1400, "Opening the failed GitHub Actions run", "Inspecting CI run", "Run #8421 · checkout-web", "browser.open"),
      activity(1700, "Finding the first failing step", "Reading failure logs", "Playwright mobile · step 14", "browser.snapshot"),
      activity(1600, "Comparing against the last green run", "Comparing CI runs", "Run #8398 → #8421", "browser.open"),
      activity(1500, "Reviewing the Playwright trace", "Inspecting browser trace", "Payment iframe never reached ready state", "browser.snapshot"),
      activity(1200, "Drafting a review note with evidence", "Preparing PR evidence", "No comment will be posted", "files.write", "file_change"),
      chunk(350, "I found the first actionable failure and compared it with the last green run.\n\n"),
      chunk(250, "**CI diagnosis**\n\n- Failing job: `checkout-web / Playwright mobile`\n- First failing step: **14 — payment iframe readiness**\n- Likely cause: the preview environment still references the pre-rename Stripe key\n- Last green run: `#8398`; current run: `#8421`\n\n"),
      chunk(200, "I also prepared a PR comment with the log and trace links. Nothing was posted or changed."),
    ],
  },
  hiring: {
    id: "hiring",
    prompt: DEMO_TRIGGER_PROMPTS.hiring,
    openingText: "I’ll check the offer, identity, workspace, device, payroll, benefits, and calendar records, then return only the items that could disrupt day one.\n\n",
    progressText: "The core accounts are present. I found a few cross-system mismatches, so I’m verifying their owners and source evidence before I summarize them.\n\n",
    steps: [
      activity(1400, "Opening the signed offer and HRIS record", "Checking new-hire record", "Jordan Lee · starts Monday", "browser.open"),
      activity(1600, "Checking identity and workspace access", "Reviewing account readiness", "Okta, Google Workspace, Slack", "browser.snapshot"),
      activity(1700, "Comparing GitHub access with the role template", "Checking engineering access", "Team assignment needs review", "browser.open"),
      activity(1500, "Reviewing laptop and benefits portals", "Checking day-one logistics", "One device exception found", "browser.snapshot"),
      activity(1200, "Building the day-one readiness map", "Preparing onboarding packet", "Accounts remain unchanged", "files.write", "file_change"),
      chunk(350, "The onboarding pass is complete. I found three items that could disrupt Jordan's first morning.\n\n"),
      chunk(250, "**Needs review**\n\n1. Laptop request is still waiting on the 16-inch exception.\n2. GitHub invite is staged for `frontend-contractors`, but the offer lists Product Engineering.\n3. Benefits location shows New York while the signed offer shows California.\n\n"),
      chunk(200, "Google Workspace, Slack, payroll, and the calendar invite are ready. I staged owner-specific follow-up notes but did not create accounts or send messages."),
    ],
  },
  operations: {
    id: "operations",
    prompt: DEMO_TRIGGER_PROMPTS.operations,
    openingText: "I’ll reconcile the renewal tracker with the live vendor portals, current seat counts, invoices, and contract terms, then flag only the exceptions that need a decision.\n\n",
    progressText: "I’ve checked the first three vendors. Two records do not line up with the live billing data, so I’m tracing the contract terms and renewal owners now.\n\n",
    steps: [
      activity(1400, "Opening the Q3 renewal tracker", "Reading renewal inventory", "Top five vendors", "browser.open"),
      activity(1700, "Checking live seat counts in vendor portals", "Auditing active seats", "Assigned versus purchased", "browser.snapshot"),
      activity(1600, "Comparing invoices with contract terms", "Reviewing renewal pricing", "Current amount versus negotiated rate", "browser.open"),
      activity(1500, "Finding owners and renewal dates", "Resolving renewal ownership", "Two renewals inside 30 days", "browser.snapshot"),
      activity(1200, "Preparing the renewal exception report", "Building renewal report", "No terms will be accepted", "files.write", "file_change"),
      chunk(350, "I reviewed the five largest SaaS renewals and attached the source evidence.\n\n"),
      chunk(250, "**Renewal exceptions**\n\n- **CloudGrid** — renews in 18 days; invoice is 12% above the contracted rate.\n- **SignalDesk** — 148 seats purchased, 103 assigned; owner confirmation needed.\n- **Formly** — renewal owner is missing from the tracker.\n\n"),
      chunk(200, "The other two vendors match their contracts and seat records. I did not approve payments, accept terms, or edit the tracker."),
    ],
  },
  research: {
    id: "research",
    prompt: DEMO_TRIGGER_PROMPTS.research,
    openingText: "I’ll reopen each cited source, compare the live page with the claim in the brief, and preserve screenshots or files anywhere the evidence may have changed.\n\n",
    progressText: "Most claims still match. I found several changes on pricing and security pages, and I’m checking the PDFs before I mark anything as verified or stale.\n\n",
    steps: [
      activity(1400, "Opening every source in the brief", "Collecting source evidence", "12 live pages · 4 PDFs", "browser.open"),
      activity(1700, "Capturing pages that may change", "Saving source snapshots", "Pricing and security pages", "browser.snapshot"),
      activity(1600, "Comparing current pages with cited claims", "Verifying brief claims", "Verified, changed, or missing", "browser.open"),
      activity(1500, "Extracting fields from the source PDFs", "Reading research PDFs", "Methods, sample sizes, limitations", "files.read", "mcp_tool"),
      activity(1200, "Updating the evidence table", "Preparing claim review", "Reviewer status preserved", "files.write", "file_change"),
      chunk(350, "I rechecked the brief against the live sources and preserved evidence for every change.\n\n"),
      chunk(250, "**Claim review**\n\n- 18 claims verified\n- 3 claims changed\n- 1 source moved behind a sales form\n- 2 PDF values need human review\n\nThe largest change is the free-plan limit: the brief says **10 seats**, while the current pricing page lists **5**.\n\n"),
      chunk(200, "The evidence table includes source URLs, access dates, screenshots, downloaded filenames, and review status."),
    ],
  },
  sales: {
    id: "sales",
    prompt: DEMO_TRIGGER_PROMPTS.sales,
    openingText: "I’ll review the CRM trail, Acme’s current site and hiring signals, then match the account with the closest relevant customer proof before I prepare your call brief.\n\n",
    progressText: "There’s a useful pattern emerging around infrastructure hiring and security timing. I’m checking the prior deal trail now so the questions are grounded in evidence, not generic talking points.\n\n",
    steps: [
      activity(1400, "Opening the Acme CRM account and call notes", "Reading deal context", "Discovery call · 2:00 PM", "browser.open"),
      activity(1700, "Checking Acme's hiring and security pages", "Researching account signals", "Three infrastructure roles found", "browser.snapshot"),
      activity(1600, "Finding the closest similar won deal", "Matching customer proof", "Series B infrastructure rollout", "browser.open"),
      activity(1500, "Reviewing pricing and procurement risks", "Checking deal risks", "Security review timing", "browser.snapshot"),
      activity(1200, "Building the source-backed call brief", "Preparing discovery brief", "CRM remains unchanged", "files.write", "file_change"),
      chunk(350, "Your Acme discovery brief is ready.\n\n"),
      chunk(250, "**What changed**\n\n- Acme is hiring three infrastructure engineers.\n- Its SOC 2 page was updated last week.\n- The last CRM note says migration risk and procurement timing blocked progress.\n- The closest proof is the Northstar infrastructure rollout.\n\n"),
      chunk(200, "**Best opener:** “I saw the infrastructure team is growing ahead of the migration. Will that team own the rollout, or inherit it after vendor selection?”\n\nI included four follow-up questions and the exact source links. Nothing was written back to the CRM."),
    ],
  },
  coding: {
    id: "coding",
    prompt: DEMO_TRIGGER_PROMPTS.coding,
    openingText: "I’ll turn the research into a focused dashboard with clear filters, an interactive comparison view, and a concise takeaway panel. I’ll first inspect the existing project and source data so the implementation fits what is already here.\n\n",
    progressText: "I’ve mapped the findings into a small data model and the primary dashboard views are taking shape. I’m wiring the interactions and checking the empty states before I run the final pass.\n\n",
    steps: [
      activity(1400, "Inspecting the project structure and research files", "Reading project context", "Finding the dashboard entry point and source material", "files.read", "mcp_tool"),
      activity(1700, "Planning the dashboard's information hierarchy", "Designing the dashboard", "Overview, filters, comparison, and takeaway views", "planning", "plan"),
      activity(1600, "Normalizing the research findings for interaction", "Preparing dashboard data", "Tags, evidence, confidence, and source fields", "files.read", "mcp_tool"),
      activity(1500, "Building the dashboard layout and filter controls", "Implementing dashboard UI", "Interactive segments and empty states", "files.write", "file_change"),
      activity(1300, "Adding comparison charts and insight panels", "Adding interactive insights", "Click through findings without losing context", "files.write", "file_change"),
      activity(1400, "Running a local build and reviewing the result", "Checking dashboard build", "Verifying the primary interaction flow", "npm run build", "command"),
      chunk(350, "The interactive research dashboard is ready for review.\n\n"),
      chunk(250, "**What it includes**\n\n- A filterable findings table with source and confidence context\n- An interactive comparison chart for the strongest themes\n- A detail panel that keeps the evidence beside each conclusion\n- Clear empty, loading, and no-match states\n\n"),
      chunk(200, "I also added a concise takeaway section so someone can understand the research without digging through every row. The build completed successfully."),
    ],
  },
  paystubs: {
    id: "paystubs",
    prompt: DEMO_TRIGGER_PROMPTS.paystubs,
    openingText: "I’ll open the payroll portal, use your saved sign-in only through the secure on-device flow, and collect this month’s paystubs. Your credential will stay hidden from the agent and I’ll keep the downloads organized for review.\n\n",
    progressText: "The payroll portal is open and the secure credential handoff is complete. I found the current pay periods and I’m checking the statement dates and downloaded file names before I wrap up.\n\n",
    steps: [
      activity(1400, "Opening the payroll portal", "Navigating to payroll", "Using the browser already signed into your work context", "browser.open"),
      activity(1500, "Finding the saved payroll credential", "Looking up saved credential", "Only masked metadata is available to the agent", "secrets.search", "mcp_tool"),
      activity(1700, "Requesting on-device credential approval", "Waiting for Touch ID", "Secure sign-in requires your confirmation", "Touch ID", "status"),
      activity(1500, "Signing in without exposing the credential", "Filling credential securely", "Credential is filled directly in the browser", "secrets.use_browser", "mcp_tool"),
      activity(1600, "Opening this month's pay statements", "Reviewing pay statements", "Checking dates, pay periods, and available PDFs", "browser.snapshot"),
      activity(1300, "Downloading and organizing the paystubs", "Saving paystub PDFs", "Files are named by pay period", "files.write", "file_change"),
      chunk(350, "I found and organized the paystubs available for this month.\n\n"),
      chunk(250, "**Paystub collection**\n\n- 2 current-month pay statements saved\n- Files named by pay period and statement date\n- Payroll portal and download source recorded for review\n\n"),
      chunk(200, "The credential was never exposed in the chat or activity log. This demo did not access a real portal or download any real documents."),
    ],
  },
  xReplies: {
    id: "xReplies",
    prompt: DEMO_TRIGGER_PROMPTS.xReplies,
    openingText: "I’ll find the relevant X post, group its comments by intent, and draft concise replies that match the conversation. I’ll prepare everything for your approval and stop before anything is sent.\n\n",
    progressText: "I’ve reviewed the comment threads and there are a few recurring questions worth answering consistently. I’m tightening the reply drafts and separating comments that should receive a more personal response.\n\n",
    steps: [
      activity(1400, "Finding the X window and recent notifications", "Inspecting your desktop", "Locating the active X conversation", "detach_macos_snapshot", "mcp_tool"),
      activity(1600, "Opening the post and collecting its comments", "Reviewing X comments", "Capturing the thread without sending anything", "detach_macos_click", "mcp_tool"),
      activity(1700, "Grouping comments by question and sentiment", "Organizing the conversation", "Questions, feedback, thanks, and follow-ups", "planning", "plan"),
      activity(1500, "Drafting replies in the X composer", "Preparing reply drafts", "Replies are staged, not sent", "detach_macos_type", "mcp_tool"),
      activity(1500, "Checking each draft for tone and duplicates", "Reviewing reply quality", "Keeping replies specific to each comment", "detach_macos_snapshot", "mcp_tool"),
      activity(1300, "Preparing the reply set for your approval", "Staging replies for approval", "Nothing will be posted automatically", "approval", "status"),
      chunk(350, "I prepared a reply set for the comments on your X post.\n\n"),
      chunk(250, "**Ready for review**\n\n- 6 thoughtful replies drafted\n- 2 repeated questions consolidated into one clear answer\n- 1 sensitive comment flagged for a personal response\n- 0 replies posted\n\n"),
      chunk(200, "The drafts are staged for your approval. I stopped before sending or publishing anything."),
    ],
  },
};

export function matchDemoScenario(prompt: string, enabled: boolean): DemoScenario | undefined {
  if (!enabled) return undefined;
  const normalized = prompt.replace(/\r\n/g, "\n").trim();
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
    activity(1200, "Reviewing connected MCP tools and permissions", "Checking connected tools", "Browser, files, and workspace capabilities", "MCP registry", "mcp_tool"),
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

function sleep(milliseconds: number) {
  return new Promise<void>((resolve) => setTimeout(resolve, milliseconds));
}
