import type { AgentRun, AgentStreamCallbacks } from "../agents/AgentAdapter";
import type { AgentActivityEvent, AgentActivityKind, AgentKind } from "../protocol/messages";

export const DEMO_TRIGGER_PROMPTS = {
  developer: "Triage the failed CI run for this PR and draft a review note with evidence.",
  hiring: "Check onboarding readiness for our new hire starting Monday.",
  operations: "Review our top five SaaS renewals and flag anything that needs attention.",
  research: "Verify the claims in this market brief against the current sources.",
  sales: "Prepare a source-backed brief for my Acme discovery call.",
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
