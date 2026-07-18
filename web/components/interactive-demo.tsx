"use client";

import { useEffect, useMemo, useState } from "react";
import {
  AppWindow,
  ArrowUp,
  Bug,
  Check,
  ChevronUp,
  CircleCheckBig,
  Files,
  Globe2,
  History,
  ListChecks,
  LockKeyhole,
  Maximize2,
  MessageSquarePlus,
  Paperclip,
  Pause,
  Play,
  RotateCcw,
  Search,
  Server,
  Square,
  WandSparkles,
  Wifi,
  X,
  Zap,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

type Phase = "enter" | "feature" | "typing" | "working" | "merging" | "notch";
type DemoFeature = "attachments" | "commands" | null;

type DemoTask = {
  id: string;
  prompt: string;
  shortLabel: string;
  activities: string[];
  notchActivity: string;
  feature: DemoFeature;
};

type DemoMenuItem = {
  id: string;
  title: string;
  subtitle: string;
  icon: LucideIcon;
};

const attachmentMenuItems: DemoMenuItem[] = [
  {
    id: "files",
    title: "Files & Folders",
    subtitle: "Search and attach workspace files",
    icon: Files,
  },
  {
    id: "skills",
    title: "Installed Skills",
    subtitle: "Run custom AI workflows and skills",
    icon: WandSparkles,
  },
  {
    id: "mcp",
    title: "Connected MCP Servers",
    subtitle: "Interact with model context servers",
    icon: Server,
  },
  {
    id: "browser",
    title: "Browser",
    subtitle: "Enable browser tools",
    icon: Globe2,
  },
  {
    id: "macos",
    title: "macOS",
    subtitle: "Control native macOS apps",
    icon: AppWindow,
  },
  {
    id: "secrets",
    title: "Secrets",
    subtitle: "Use saved credentials with Touch ID",
    icon: LockKeyhole,
  },
];

const commandMenuItems: DemoMenuItem[] = [
  {
    id: "explain",
    title: "Explain",
    subtitle: "/explain - Break down the selected context clearly",
    icon: Zap,
  },
  {
    id: "simplify",
    title: "Simplify",
    subtitle: "/simplify - Rewrite in simpler language",
    icon: Zap,
  },
  {
    id: "code-review",
    title: "Code Review",
    subtitle: "/code-review - Review for bugs, risks, and missing tests",
    icon: Zap,
  },
  {
    id: "compact-context",
    title: "Compact Context",
    subtitle: "/compact-context - Summarize the useful context",
    icon: ListChecks,
  },
  {
    id: "debug",
    title: "Debug",
    subtitle: "/debug - Trace the likely cause and propose a fix",
    icon: Bug,
  },
  {
    id: "plan",
    title: "Plan",
    subtitle: "/plan - Make a concise implementation plan first",
    icon: ListChecks,
  },
];

const demoTasks: DemoTask[] = [
  {
    id: "operations",
    prompt: "Review our top five SaaS renewals and flag anything that needs attention.",
    shortLabel: "SaaS renewals",
    activities: ["Planning the task", "Checking connected tools", "Using MCP registry"],
    notchActivity: "Using MCP registry",
    feature: "attachments",
  },
  {
    id: "developer",
    prompt: "Triage the failed CI run for this PR and draft a review note with evidence.",
    shortLabel: "CI triage",
    activities: ["Planning the task", "Opening the failed CI run", "Using browser.snapshot"],
    notchActivity: "Using browser.snapshot",
    feature: "commands",
  },
  {
    id: "sales",
    prompt: "Prepare a source-backed brief for my Acme discovery call.",
    shortLabel: "Discovery brief",
    activities: ["Planning the task", "Reviewing CRM context", "Using files.write"],
    notchActivity: "Using files.write",
    feature: null,
  },
];

const phaseOrder: Phase[] = ["enter", "feature", "typing", "working", "merging", "notch"];
const phaseDuration: Record<Phase, number> = {
  enter: 1450,
  feature: 2600,
  typing: 3600,
  working: 3550,
  merging: 760,
  notch: 3650,
};

function DetachedMarkLoader() {
  return (
    <span className="demo-detached-loader" aria-hidden="true">
      <svg viewBox="0 0 1024 1024" focusable="false">
        <path
          className="demo-detached-panel demo-detached-panel-left"
          d="M244 329C244 286 280 258 319 269C354 279 400 302 443 322C458 329 468 342 472 358L538 600C544 622 533 640 514 649L344 719C297 739 244 714 244 666Z"
        />
        <path
          className="demo-detached-panel demo-detached-panel-right"
          d="M780 317C780 271 732 245 691 263L546 338C527 348 518 365 523 384L589 629C594 647 604 658 620 666L688 704C729 727 780 704 780 660Z"
        />
      </svg>
    </span>
  );
}

function DemoFeatureMenu({ kind, step }: { kind: Exclude<DemoFeature, null>; step: number }) {
  if (kind === "attachments") {
    const highlightedId = step === 0 ? "files" : step === 1 ? "browser" : "macos";

    return (
      <aside className="demo-feature-menu" aria-label="Attachment menu">
        {attachmentMenuItems.map((item) => (
          <DemoFeatureMenuRow
            item={item}
            highlighted={item.id === highlightedId}
            selected={(item.id === "browser" && step >= 1) || (item.id === "macos" && step >= 2)}
            key={item.id}
          />
        ))}
      </aside>
    );
  }

  const highlightedId = step === 0 ? "test" : "code-review";

  return (
    <aside className="demo-feature-menu demo-command-menu" aria-label="Command menu">
      <span className="demo-feature-section-label">Quick Actions</span>
      <DemoFeatureMenuRow
        item={{
          id: "test",
          title: "test",
          subtitle: "open terminal with echoing the text:",
          icon: CircleCheckBig,
        }}
        highlighted={highlightedId === "test"}
      />
      <span className="demo-feature-section-label">Commands</span>
      {commandMenuItems.map((item) => (
        <DemoFeatureMenuRow
          item={item}
          highlighted={item.id === highlightedId}
          key={item.id}
        />
      ))}
    </aside>
  );
}

function DemoFeatureMenuRow({
  item,
  highlighted,
  selected = false,
}: {
  item: DemoMenuItem;
  highlighted: boolean;
  selected?: boolean;
}) {
  const Icon = item.icon;

  return (
    <div className={`demo-feature-row ${highlighted ? "is-highlighted" : ""}`}>
      <Icon className="demo-feature-row-icon" />
      <span className="demo-feature-row-copy">
        <strong>{item.title}</strong>
        <small>{item.subtitle}</small>
      </span>
      {selected && <Check className="demo-feature-row-check" />}
    </div>
  );
}

export default function InteractiveDemo() {
  const [taskIndex, setTaskIndex] = useState(0);
  const [phase, setPhase] = useState<Phase>("enter");
  const [typedPrompt, setTypedPrompt] = useState("");
  const [activityIndex, setActivityIndex] = useState(0);
  const [featureStep, setFeatureStep] = useState(0);
  const [playing, setPlaying] = useState(true);

  const task = demoTasks[taskIndex];
  const notchIsActive = phase === "merging" || phase === "notch";

  const notchTasks = useMemo(() => {
    const lastVisibleIndex = phase === "merging" || phase === "notch" ? taskIndex : taskIndex - 1;
    if (lastVisibleIndex < 0) return [];
    return demoTasks
      .map((item, index) => ({ ...item, index }))
      .filter((item) => item.index <= lastVisibleIndex)
      .reverse();
  }, [phase, taskIndex]);

  useEffect(() => {
    if (!playing) return;

    const timer = window.setTimeout(() => {
      if (phase === "notch") {
        const nextTask = (taskIndex + 1) % demoTasks.length;
        setTaskIndex(nextTask);
        setTypedPrompt("");
        setActivityIndex(0);
        setFeatureStep(0);
        setPhase("enter");
        return;
      }

      const nextPhase = phase === "enter" && task.feature === null
        ? "typing"
        : phaseOrder[phaseOrder.indexOf(phase) + 1];
      if (nextPhase === "enter" || nextPhase === "typing") {
        setTypedPrompt("");
      }
      if (nextPhase === "feature") {
        setFeatureStep(0);
      }
      if (nextPhase !== "working") {
        setActivityIndex(0);
      }
      setPhase(nextPhase);
    }, phaseDuration[phase]);

    return () => window.clearTimeout(timer);
  }, [phase, playing, task.feature, taskIndex]);

  useEffect(() => {
    if (phase !== "typing") {
      return;
    }

    let character = 0;
    let typing: number | undefined;
    const typingDelay = window.setTimeout(() => {
      typing = window.setInterval(() => {
        character += 1;
        setTypedPrompt(task.prompt.slice(0, character));
        if (character >= task.prompt.length && typing !== undefined) {
          window.clearInterval(typing);
        }
      }, 34);
    }, 220);

    return () => {
      window.clearTimeout(typingDelay);
      if (typing !== undefined) window.clearInterval(typing);
    };
  }, [phase, task]);

  useEffect(() => {
    if (phase !== "feature" || !playing) {
      return;
    }

    const firstSelection = window.setTimeout(() => setFeatureStep(1), 650);
    const secondSelection = window.setTimeout(() => setFeatureStep(2), 1450);

    return () => {
      window.clearTimeout(firstSelection);
      window.clearTimeout(secondSelection);
    };
  }, [phase, playing, taskIndex]);

  useEffect(() => {
    if (phase !== "working") {
      return;
    }

    const activity = window.setInterval(() => {
      setActivityIndex((current) => Math.min(current + 1, task.activities.length - 1));
    }, 1100);

    return () => window.clearInterval(activity);
  }, [phase, task]);

  function replay() {
    setTaskIndex(0);
    setPhase("enter");
    setTypedPrompt("");
    setActivityIndex(0);
    setFeatureStep(0);
    setPlaying(true);
  }

  // Dynamic notch configuration
  let notchWidth = "w-[28%] sm:w-[20%]";
  let notchHeight = "h-[5%] sm:h-[6%]";
  let notchRadius = "rounded-b-[1rem] sm:rounded-b-[1.45rem]";

  if (phase === "merging" || phase === "notch") {
    notchWidth = "w-[82%] sm:w-[40%]";
    notchRadius = "rounded-b-[1.5rem] sm:rounded-b-[1.65rem]";
    if (taskIndex === 0) {
      notchHeight = "h-[24%] sm:h-[17.5%]";
    } else if (taskIndex === 1) {
      notchHeight = "h-[36%] sm:h-[26%]";
    } else {
      notchHeight = "h-[48%] sm:h-[34.5%]";
    }
  }

  const notchContentClass = notchIsActive
    ? "opacity-100 translate-y-0"
    : "opacity-0 -translate-y-[10px]";

  let featurePrefix = "";
  if (task.feature === "attachments") {
    if (phase === "feature") {
      featurePrefix = featureStep === 0 ? "@" : featureStep === 1 ? "@Browser " : "@Browser @macOS ";
    } else if (phase === "typing") {
      featurePrefix = "@Browser @macOS ";
    }
  } else if (task.feature === "commands") {
    if (phase === "feature") {
      featurePrefix = featureStep === 0 ? "/" : featureStep === 1 ? "/code" : "/code-review ";
    } else if (phase === "typing") {
      featurePrefix = "/code-review ";
    }
  }

  const isWorking = phase === "working" || phase === "merging";
  const toolbarBtnClass = `grid place-items-center border-0 rounded-full text-[#17100a] font-inherit p-0 transition-colors
  duration-250 ease-in-out
    w-5 h-5
    ${isWorking ? "bg-[#ff4653]" : "bg-[#ff7900]"}`;

  const toolbarBtnSvgClass = `w-[62%] h-[62%]
    ${isWorking ? "fill-[#171012] stroke-0" : "[stroke-width:2.2]"}`;

  return (
    <div className="">
      <div
        className="demo-frame scale-80 relative overflow-hidden border border-black/16 bg-[#090909] shadow-[0_28px_80px_rgba(37,29,22,0.17),0_0_0_7px_rgba(255,255,255,0.5)] aspect-[3/4] sm:aspect-[16/9.6] rounded-[1.25rem] sm:rounded-[2rem]"
        data-phase={phase}
        data-task={taskIndex}
        data-feature={task.feature ?? "none"}
      >
        <div className="absolute inset-0 overflow-hidden text-[#f7f7f7] text-left [font-synthesis:none]">
          <img
            src="image1.png"
            alt="demo-Wallpaper"
            className="w-full h-full object-cover"
          />

          <div className="flex items-center px-6 w-full mt-2 text-black absolute top-0 left-0">
              <div className="flex items-center gap-2 w-1/2">
                <h1 className="text-xl"></h1>
                <h1 className="text-base apple font-semibold tracking-tight">Detach</h1>
              </div>
              <div className="flex items-center justify-end gap-2 w-1/2">
                <Search className="w-4 h-4 stroke-[2.5]"/>
                <Wifi className="w-4 h-4 stroke-[2.5]"/>
                <h1 className="text-base apple font-semibold tracking-tight">09:41</h1>
              </div>
          </div>

          <section
            className={`absolute z-20 top-0 left-1/2 -translate-x-1/2 origin-top
bg-black overflow-hidden ${notchWidth} ${notchHeight} ${notchRadius}`}
            style={{
              transition:
                "width 720ms cubic-bezier(0.22, 1, 0.36, 1), height 720ms cubic-bezier(0.22, 1, 0.36, 1), border-radius 600ms ease, opacity 300ms ease, transform 500ms cubic-bezier(0.34, 1.56, 0.64, 1)",
            }}
            aria-label="Detach task notch"
          >
            <div className="h-[24px] sm:h-[clamp(22px,4%,32px)]" aria-hidden="true" />
            <div
              className={`demo-notch-content text-left pb-3 sm:pb-4 ${notchContentClass}`}
            >
              <header className="flex items-center justify-between px-5">
                <span className="text-xs font-semibold">
                  TASKS
                </span>
                <button
                  type="button"
                  tabIndex={-1}
                  className="grid place-items-center w-[clamp(1.55rem,2.6vw,2rem)] h-[clamp(1.55rem,2.6vw,2rem)] border-0 rounded-full p-0 font-inherit"
                  aria-label="Dismiss task notch"
                >
                  <X className="w-[48%] h-[48%] [stroke-width:1.6]" />
                </button>
              </header>
              <div className="">
                {notchTasks.map((notchTask) => {
                  const isCurrent = notchIsActive && notchTask.index === taskIndex;
                  return (
                    <div
                      className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-4 border-t border-white/10 first:border-white/4 h-14 px-5"
                      key={notchTask.id}
                    >
                      <div className="min-w-0 flex flex-col items-start gap-0 text-left">
                        <strong className="w-full overflow-hidden text-white font-[430] text-left text-ellipsis whitespace-nowrap text-sm">
                          {notchTask.prompt}
                        </strong>
                        <span className="w-full overflow-hidden text-white/50 font-[380] text-left text-ellipsis whitespace-nowrap text-xs">
                          {isCurrent ? notchTask.notchActivity : "Completed"}
                        </span>
                      </div>
                      {isCurrent ? (
                        <span
                          className="relative grid place-items-center w-[clamp(1.5rem,2.4vw,1.8rem)] h-[clamp(1.5rem,2.4vw,1.8rem)] flex-none"
                          aria-label="Running"
                        >
                          <DetachedMarkLoader />
                        </span>
                      ) : (
                        <span
                          className="grid place-items-center w-[clamp(1.05rem,1.7vw,1.3rem)] h-[clamp(1.05rem,1.7vw,1.3rem)] rounded-full bg-[#38df68] text-[#07170b]"
                          aria-label="Completed"
                        >
                          <Check className="w-[42%] h-[42%] [stroke-width:2.5]" />
                        </span>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
            {/* <div className="h-[24px] sm:h-[clamp(22px,4%,32px)]" aria-hidden="true" /> */}
          </section>

          <div
            className="demo-chat-group absolute z-12 w-[78%] text-left sm:w-[40%]"
          >
            {task.feature && (
              <DemoFeatureMenu kind={task.feature} step={featureStep} />
            )}

            <div
              className="demo-task-number absolute left-3 grid h-6 w-6 place-items-center rounded-full bg-[#111112]/97 text-xs font-[430] text-[#f4f4f4]"
              aria-hidden="true"
            >
              {taskIndex + 1}
            </div>

            <section
              className="demo-working-window absolute left-0 right-0 z-[2] flex h-16 items-start gap-[clamp(0.7rem,1.4vw,1rem)] overflow-hidden rounded-xl bg-[#0f0f10]/98 p-4 text-left"
              aria-label={`Detach working: ${task.activities[activityIndex]}`}
            >
              {/* <div className="w-[clamp(1.45rem,2.7vw,2rem)] h-1 flex-none mt-[0.55rem] rounded-2xl bg-[#aaa8ab]
              animate-[demo-working-pulse_1.25s_ease-in-out_infinite]" /> */}
              <div className="flex flex-col">
                <strong className="text-[#d8d6d9] text-xs">
                  Working...
                </strong>
                <span className="text-[#747277] text-[clamp(0.5rem,0.82vw,0.64rem)] font-[360]">
                  {task.activities[activityIndex]}
                </span>
              </div>
            </section>

            <section
              className="relative overflow-hidden rounded-xl bg-[#0f0f10]/98
              text-left h-[8.2rem] sm:h-[clamp(5.8rem,8.5vw,6.8rem)] pt-[0.9rem] px-[1rem]
              sm:pt-[clamp(0.72rem,1.35vw,1rem)] sm:px-[clamp(0.8rem,1.55vw,1.1rem)]"
              aria-label="Detach floating chat window"
            >
              <button
                className="absolute grid place-items-center border-0 p-0 bg-transparent text-[#929094] leading-none top-[clamp(0.65rem,1.7vw,1.1rem)] right-[clamp(0.9rem,2.2vw,1.55rem)]"
                type="button"
                tabIndex={-1}
                aria-label="Close floating chat"
              >
                <X className="w-[clamp(0.85rem,1.35vw,1.05rem)] h-[clamp(0.85rem,1.35vw,1.05rem)] [stroke-width:1.45]" />
              </button>
              <div className="w-[calc(100%-1.65rem)] text-[#f4f3f5] font-[380] leading-[1.42] text-left min-h-[52%] sm:min-h-[48%] text-[0.74rem] sm:text-[clamp(0.62rem,1vw,0.82rem)]">
                {phase === "working" || phase === "merging" ? (
                  <span className="text-[#8e8c90] font-[380]">Anything ..</span>
                ) : (
                  <>
                    {featurePrefix && (
                      <span className="text-[#ff7900]">{featurePrefix}</span>
                    )}
                    <span>{typedPrompt}</span>
                    {(phase === "feature" || phase === "typing") && (
                      <i
                        className="inline-block w-[2px] h-[1.15em] ml-[2px] bg-white align-[-0.15em] animate-[demo-caret-blink_800ms_step-end_infinite]"
                        aria-hidden="true"
                      />
                    )}
                  </>
                )}
              </div>
              <footer className="absolute flex items-center justify-between gap-4 left-[1rem] sm:left-[clamp(0.8rem,1.55vw,1.1rem)] right-[1rem] sm:right-[clamp(0.8rem,1.55vw,1.1rem)] bottom-[0.72rem] sm:bottom-[clamp(0.58rem,1vw,0.75rem)]">
                <div className="flex items-center gap-[0.42rem] sm:gap-[clamp(0.32rem,0.65vw,0.5rem)]">
                  <strong className="text-[#f4f4f4] font-[430] text-[0.48rem] sm:text-[clamp(0.5rem,0.82vw,0.68rem)]">
                    Codex
                  </strong>
                  <ChevronUp className="text-[#7d7b80] [stroke-width:1.5] w-[0.45rem] sm:w-[clamp(0.48rem,0.75vw,0.6rem)] h-[0.45rem] sm:h-[clamp(0.48rem,0.75vw,0.6rem)]" />
                  <strong className="text-[#f4f4f4] font-[430] text-[0.48rem] sm:text-[clamp(0.5rem,0.82vw,0.68rem)]">
                    GPT-5.4-Mini
                  </strong>
                  <ChevronUp className="text-[#7d7b80] [stroke-width:1.5] w-[0.45rem] sm:w-[clamp(0.48rem,0.75vw,0.6rem)] h-[0.45rem] sm:h-[clamp(0.48rem,0.75vw,0.6rem)]" />
                </div>
                <div className="flex items-center text-[#f1f0f2] gap-[0.47rem] sm:gap-[clamp(0.45rem,0.9vw,0.7rem)]" aria-hidden="true">
                  <Paperclip className="demo-attachment-trigger [stroke-width:1.6] w-[0.85rem] sm:w-[clamp(0.82rem,1.15vw,1rem)] h-[0.85rem] sm:h-[clamp(0.82rem,1.15vw,1rem)]" />
                  <History className="[stroke-width:1.6] w-[0.85rem] sm:w-[clamp(0.82rem,1.15vw,1rem)] h-[0.85rem] sm:h-[clamp(0.82rem,1.15vw,1rem)]" />
                  <MessageSquarePlus className="[stroke-width:1.6] w-[0.85rem] sm:w-[clamp(0.82rem,1.15vw,1rem)] h-[0.85rem] sm:h-[clamp(0.82rem,1.15vw,1rem)]" />
                  <Maximize2 className="[stroke-width:1.6] w-[0.85rem] sm:w-[clamp(0.82rem,1.15vw,1rem)] h-[0.85rem] sm:h-[clamp(0.82rem,1.15vw,1rem)]" />
                  <button className={toolbarBtnClass} tabIndex={-1}>
                    {phase === "working" || phase === "merging" ? (
                      <Square className={toolbarBtnSvgClass} />
                    ) : (
                      <ArrowUp className={toolbarBtnSvgClass} />
                    )}
                  </button>
                </div>
              </footer>
            </section>
          </div>

          <div className="absolute bottom-0 left-0 right-0 z-[3] flex flex-col items-center gap-[10px] px-4 pt-0 pb-[9px] sm:pb-[18px]">
            <div className="w-full flex justify-center">
              <div className="flex items-center relative border border-white/18 [backdrop-filter:blur(40px)_saturate(170%)] bg-gradient-to-b from-white/15 to-white/6 shadow-[0_8px_32px_rgba(0,0,0,0.25),inset_0_1px_0_rgba(255,255,255,0.15),inset_0_-1px_0_rgba(0,0,0,0.08)] gap-[4px] px-[7px] py-[5px] rounded-[15px] sm:gap-[clamp(5px,0.8vw,9px)] sm:pt-[clamp(6px,0.8vw,9px)] sm:pb-[clamp(6px,0.8vw,9px)] sm:px-[clamp(9px,1.2vw,14px)] sm:rounded-[22px]">
                {[
                  { src: "/icons/githubApp.webp", alt: "Github app icon", glow: 0 },
                  { src: "/icons/googlecalendarApp.png", alt: "Google Calender app icon", glow: 0 },
                  { src: "/icons/diaApp.webp", alt: "Dia app icon", glow: 0 },
                  { src: "/icons/slackApp.webp", alt: "Slack app icon", glow: 0 },
                  { src: "/icons/notionApp.webp", alt: "Notion app icon", glow: 1 },
                  { src: "/icons/imessageApp.webp", alt: "Messages app icon", glow: 0 },
                  { src: "/icons/linearApp.webp", alt: "Linear app icon", glow: 0 },
                  { src: "/icons/gmailApp.webp", alt: "Gmail app icon", glow: 0 },
                  { src: "/icons/googleDocsApp.webp", alt: "Docs app icon", glow: 0 },
                  { src: "/icons/figmaApp.webp", alt: "Figma app icon", glow: 0 },
                ].map((icon, i) => (
                  <div
                    key={i}
                    className="relative flex flex-col items-center transition-transform duration-200 [transition-timing-function:cubic-bezier(0.34,1.56,0.64,1)]"
                  >
                    <img
                      src={icon.src}
                      alt={icon.alt}
                      loading="lazy"
                      width={44}
                      height={44}
                      className="object-contain w-[24px] h-[24px] sm:w-[clamp(27px,3.4vw,40px)] sm:h-[clamp(27px,3.4vw,40px)]"
                    />
                    <div
                      style={{ opacity: icon.glow }}
                      className="absolute -bottom-[5px] w-[3px] h-[3px] rounded-full bg-white/88"
                    />
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* <div className="flex items-center justify-between pt-[1.15rem] px-[0.35rem] pb-0 text-[#77746e] text-[0.7rem]">
        <div className="flex items-center gap-[0.55rem]">
          <span className="w-[0.45rem] h-[0.45rem] rounded-full bg-[#ff7900] shadow-[0_0_0_4px_rgba(255,121,0,0.1)]" />
          <strong className="text-[#2f2d2a] font-[650]">
            {task.shortLabel}
          </strong>
          <span>
            {taskIndex + 1} of {demoTasks.length}
          </span>
        </div>
        <div className="flex items-center gap-[0.55rem]">
          <button
            type="button"
            className="grid place-items-center w-8 h-8 border border-[#d4d1ca] rounded-full bg-white/68 text-[#403e3a] font-inherit text-[0.72rem] font-[650] cursor-pointer"
            onClick={() => setPlaying((current) => !current)}
            aria-label={playing ? "Pause animation" : "Play animation"}
          >
            {playing ? (
              <Pause className="w-[42%] h-[42%] [stroke-width:1.7]" />
            ) : (
              <Play className="w-[42%] h-[42%] [stroke-width:1.7]" />
            )}
          </button>
          <button
            type="button"
            className="grid place-items-center w-8 h-8 border border-[#d4d1ca] rounded-full bg-white/68 text-[#403e3a] font-inherit text-[0.72rem] font-[650] cursor-pointer"
            onClick={replay}
            aria-label="Replay animation"
          >
            <RotateCcw className="w-[42%] h-[42%] [stroke-width:1.7]" />
          </button>
        </div>
      </div> */}
    </div>
  );
}
