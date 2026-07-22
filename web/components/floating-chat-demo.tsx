"use client";

import { useEffect, useState } from "react";
import {
  ArrowUp,
  ChevronUp,
  Clock3,
  Copy,
  Maximize2,
  MessageSquarePlus,
  Paperclip,
  Square,
  X,
} from "lucide-react";

type FloatingDemoKind = "coding" | "browser" | "macos";

type Scenario = {
  prompt: string;
  planningLabel: string;
  workingCopy: string;
  activities: string[];
  completionLead: string;
  completionTitle: string;
  completionPoints: string[];
  completionTail: string;
};

const scenarios: Record<FloatingDemoKind, Scenario> = {
  coding: {
    prompt: "Build a dashboard to make our research findings interactive.",
    planningLabel: "Understanding the request and planning the run",
    workingCopy:
      "I’ll turn the research into a focused dashboard with clear filters, an interactive comparison view, and a concise takeaway panel. I’ll first inspect the existing project and source data so the implementation fits what is already here.",
    activities: [
      "Checking workspace memory for relevant context",
      "Reviewing connected MCP tools and permissions",
      "Inspecting the existing project and source data",
      "Building the interactive dashboard",
    ],
    completionLead:
      "I’ve mapped the findings into a small data model and the primary dashboard views are taking shape. I’m wiring the interactions and checking the empty states before I run the final pass.",
    completionTitle: "The interactive research dashboard is ready for review.",
    completionPoints: [
      "A filterable findings table with source and confidence context",
      "An interactive comparison chart for the strongest themes",
      "A detail panel that keeps the evidence beside each conclusion",
      "Clear empty, loading, and no-match states",
    ],
    completionTail:
      "I also added a concise takeaway section so someone can understand the research without digging through every row. The build completed successfully.",
  },
  browser: {
    prompt: "Get my paystubs for this month.",
    planningLabel: "Understanding the request and planning the run",
    workingCopy:
      "I’ll find this month’s paystubs through your signed-in payroll portal. I’ll use the secure on-device credential flow if it is needed, then organize the downloaded statements for you.",
    activities: [
      "Checking workspace memory for relevant context",
      "Reviewing connected browser tools and permissions",
      "Opening the payroll portal",
      "Finding the current-month statements",
    ],
    completionLead:
      "The secure handoff is complete and I found the two current-month statements. I checked that both downloads opened correctly before organizing them.",
    completionTitle: "Your current-month paystubs are ready for review.",
    completionPoints: [
      "Two PDF paystubs downloaded from the payroll portal",
      "Files named consistently and kept together",
      "Both PDFs opened successfully after download",
      "Your saved credential remained private on this Mac",
    ],
    completionTail:
      "I did not change any payroll details or submit anything on your behalf.",
  },
  macos: {
    prompt: "Reply to all comments my X post has received.",
    planningLabel: "Understanding the request and planning the run",
    workingCopy:
      "I’ll review the comment threads, group the recurring questions, and draft thoughtful replies in your voice. I’ll stop with the drafts staged for review before anything is posted.",
    activities: [
      "Checking workspace memory for relevant context",
      "Reviewing connected desktop tools and permissions",
      "Reading the comment threads",
      "Drafting replies for your approval",
    ],
    completionLead:
      "I found a few recurring questions and one sensitive thread. The drafts now reflect the different tones each conversation needs, with the sensitive reply called out separately.",
    completionTitle: "Six replies are staged for your review.",
    completionPoints: [
      "Four concise answers to recurring product questions",
      "One thank-you reply for a detailed customer story",
      "One sensitive-thread draft flagged for closer review",
      "No comments have been posted",
    ],
    completionTail:
      "Everything is ready in the composer when you want to review and approve the replies.",
  },
};

const activityDelayMs = 2_350;
const replayDelayMs = 5_000;

export default function FloatingChatDemo({ kind }: { kind: FloatingDemoKind }) {
  const scenario = scenarios[kind];
  const [typedLength, setTypedLength] = useState(0);
  const [activityIndex, setActivityIndex] = useState(-1);
  const [isComplete, setIsComplete] = useState(false);
  const [run, setRun] = useState(0);

  useEffect(() => {
    const timers: number[] = [];
    const typeIntervalMs = 10;
    const typingDuration = scenario.workingCopy.length * typeIntervalMs + 700;

    const typingTimer = window.setInterval(() => {
      setTypedLength((current) => {
        if (current >= scenario.workingCopy.length) {
          window.clearInterval(typingTimer);
          return current;
        }
        return current + 1;
      });
    }, typeIntervalMs);

    scenario.activities.forEach((_, index) => {
      timers.push(
        window.setTimeout(
          () => setActivityIndex(index),
          typingDuration + 260 + index * activityDelayMs
        )
      );
    });

    const completionAt = typingDuration + scenario.activities.length * activityDelayMs + 420;
    timers.push(window.setTimeout(() => setIsComplete(true), completionAt));
    timers.push(
      window.setTimeout(() => {
        setTypedLength(0);
        setActivityIndex(-1);
        setIsComplete(false);
        setRun((current) => current + 1);
      }, completionAt + replayDelayMs)
    );

    return () => {
      window.clearInterval(typingTimer);
      timers.forEach(window.clearTimeout);
    };
  }, [run, scenario]);

  const streamedCopy = scenario.workingCopy.slice(0, typedLength);
  const visibleActivities = scenario.activities.slice(0, Math.max(activityIndex + 1, 0));

  return (
    <div
      className="mx-auto w-full max-w-[48rem] px-3 py-8 sm:px-6 sm:py-10"
      aria-label={`${scenario.prompt} floating Detach demo`}
    >
      <div className="mb-14 ml-8 grid size-10 place-items-center rounded-full border border-white/35 bg-[#171717] text-[1rem] font-medium text-white shadow-[0_0.5rem_1rem_rgba(0,0,0,0.18)]">
        1
      </div>

      <section className="overflow-hidden rounded-[1.7rem] border border-white/20 bg-[#1a1a1a] text-white shadow-[0_1.5rem_3.75rem_rgba(0,0,0,0.28)]">
        {isComplete ? (
          <div className="px-7 py-7 text-[clamp(1rem,1.7vw,1.35rem)] font-medium leading-[1.58] tracking-[-0.025em] sm:px-9 sm:py-8">
            <p className="m-0">{scenario.completionLead}</p>
            <p className="mb-4 mt-1.5">
              {scenario.completionTitle} <strong>What it includes</strong>
            </p>
            <ul className="mb-5 space-y-3 pl-7">
              {scenario.completionPoints.map((point) => (
                <li key={point}>{point}</li>
              ))}
            </ul>
            <p className="m-0">{scenario.completionTail}</p>
          </div>
        ) : (
          <div className="min-h-[22rem] px-7 py-7 sm:min-h-[24rem] sm:px-9 sm:py-8">
            {activityIndex >= 0 ? (
              <p className="mb-5 text-[0.92rem] font-medium text-white/60 sm:text-[1rem]">
                {scenario.planningLabel}
              </p>
            ) : null}

            <p className="m-0 max-w-[97%] text-[clamp(1rem,1.7vw,1.35rem)] font-medium leading-[1.58] tracking-[-0.025em]">
              {streamedCopy}
              {typedLength < scenario.workingCopy.length ? (
                <span className="ml-1 inline-block h-[1.05em] w-px animate-pulse bg-white/80 align-[-0.18em]" />
              ) : null}
            </p>

            {visibleActivities.length > 0 ? (
              <div className="mt-7 space-y-4">
                {visibleActivities.map((activity, index) => {
                  const isActive = index === activityIndex;
                  return (
                    <div
                      className={`flex items-center gap-3 text-[0.92rem] font-medium sm:text-[1rem] ${
                        isActive ? "text-white/85" : "text-white/55"
                      }`}
                      key={activity}
                    >
                      {isActive ? (
                        <span className="h-[3px] w-9 overflow-hidden rounded-full bg-white/30">
                          <span className="block h-full w-1/2 animate-[pulse_1.25s_ease-in-out_infinite] rounded-full bg-white/90" />
                        </span>
                      ) : (
                        <span className="h-[3px] w-9 rounded-full bg-transparent" />
                      )}
                      <span>{activity}</span>
                    </div>
                  );
                })}
              </div>
            ) : null}
          </div>
        )}

        {isComplete ? (
          <div className="flex items-center gap-2 border-t border-white/10 px-7 py-4 text-[0.9rem] font-medium text-white/60 sm:px-9">
            <Copy className="size-5" strokeWidth={1.65} />
            Copy
          </div>
        ) : null}
      </section>

      <section className="mt-6 overflow-hidden rounded-[1.7rem] border border-white/20 bg-[#1a1a1a] text-white shadow-[0_1.5rem_3.75rem_rgba(0,0,0,0.28)]">
        <div className="flex min-h-[5.5rem] items-start justify-between px-7 pb-3 pt-6 sm:px-8">
          <span className="flex items-center text-[clamp(1rem,1.7vw,1.35rem)] font-medium tracking-[-0.025em] text-white/60">
            {!isComplete ? <span className="mr-2 h-[1.05em] w-px bg-white/85" /> : null}
            Anything ..
          </span>
          <X className="mt-1 size-6 text-white/55" strokeWidth={1.6} />
        </div>

        <footer className="flex items-center gap-5 px-7 pb-5 sm:px-8">
          <button className="flex items-center gap-2 text-[0.9rem] font-semibold tracking-[-0.02em] text-white" type="button">
            Codex <ChevronUp className="size-4 text-white/55" strokeWidth={1.8} />
          </button>
          <button className="flex items-center gap-2 text-[0.9rem] font-semibold tracking-[-0.02em] text-white" type="button">
            GPT-5.4-Mini <ChevronUp className="size-4 text-white/55" strokeWidth={1.8} />
          </button>
          <div className="ml-auto flex items-center gap-4 text-white">
            <Paperclip className="size-6" strokeWidth={1.75} />
            <Clock3 className="size-6" strokeWidth={1.75} />
            <MessageSquarePlus className="size-6" strokeWidth={1.75} />
            <Maximize2 className="size-6" strokeWidth={1.75} />
            <span
              className={`grid size-9 place-items-center rounded-full ${
                isComplete ? "bg-white/20 text-white/60" : "bg-[#ff4d58] text-[#351315]"
              }`}
            >
              {isComplete ? <ArrowUp className="size-5" strokeWidth={2.2} /> : <Square className="size-4 fill-current" strokeWidth={2.4} />}
            </span>
          </div>
        </footer>
      </section>
    </div>
  );
}
