"use client";

import { useState } from "react";
import {
  ArrowUp,
  Check,
  ChevronDown,
  ChevronUp,
  History,
  Maximize2,
  MessageSquarePlus,
  Paperclip,
  X,
} from "lucide-react";
import TypewriterPrompt from "@/components/typewriter-prompt";

const agents = ["Codex", "Claude", "Grok"];

const modelsByAgent: Record<string, string[]> = {
  Codex: [
    "Default",
    "GPT-5.6-Sol",
    "GPT-5.6-Terra",
    "GPT-5.6-Luna",
    "GPT-5.5",
    "GPT-5.4",
    "GPT-5.4-Mini",
    "Codex Auto Review",
  ],
  Claude: [
    "Default",
    "Fable",
    "Claude Opus 4",
    "Claude Sonnet 4.5",
    "Claude Sonnet 4",
    "Claude Haiku 3.5",
    "Claude Haiku 3",
  ],
  Grok: [
    "Default",
    "Grok 4.5",
    "Grok 3 fast",
    "Grok 4"
  ],
  // OpenCode: [
  //   "Default",
  //   "GPT-5.6-Sol",
  //   "Claude Sonnet 4.5",
  //   "Gemini 2.5 Pro",
  //   "Grok 3",
  // ],
};

type OpenMenu = "agent" | "model" | null;

export default function AgentSelectorDemo() {
  const [agentIndex, setAgentIndex] = useState(0);
  const [modelIndex, setModelIndex] = useState(0);
  const [openMenu, setOpenMenu] = useState<OpenMenu>("model");

  const currentAgent = agents[agentIndex];
  const currentModels = modelsByAgent[currentAgent] ?? [];

  return (
    <section
      className="relative h-full max-h-24 max-md:h-32 max-md:max-h-none w-full overflow-visible rounded-lg bg-white p-2.5 max-md:mx-3 mx-5 text-left text-black"
      aria-label="Detach floating chat window with agent and model selectors"
    >
      <button
        className="absolute right-3 top-3 z-10 grid place-items-center border-0 bg-transparent p-0 leading-none text-[#929094]"
        type="button"
        tabIndex={-1}
        aria-label="Close floating chat"
      >
        <X className="h-4 w-4 [stroke-width:1.45]" />
      </button>

     <div className="relative h-full flex flex-col">
      <div className="w-[calc(100%-1.65rem)] text-[#000000] font-[380] leading-[1.42] text-left text-[0.74rem] sm:text-[clamp(0.62rem,1vw,0.82rem)] flex-1 min-h-[4rem]">
        Ask Detach anything ...
      </div>
    </div>

      <footer
        className="absolute bottom-0 left-[1rem] right-[1rem] flex items-center justify-between gap-3 pb-2"
        aria-label="Agent and model selectors"
      >
        <div className="relative flex items-center gap-[0.42rem] sm:gap-[clamp(0.32rem,0.65vw,0.5rem)]">
          <SelectorButton
            label={agents[agentIndex]}
            isOpen={openMenu === "agent"}
            onClick={() => setOpenMenu(openMenu === "agent" ? null : "agent")}
          />
          <SelectorButton
            label={currentModels[modelIndex] ?? currentModels[0]}
            isOpen={openMenu === "model"}
            onClick={() => setOpenMenu(openMenu === "model" ? null : "model")}
          />

          {openMenu === "agent" ? (
            <SelectorMenu
              items={agents}
              selectedIndex={agentIndex}
              className="left-0"
              onSelect={(index) => {
                setAgentIndex(index);
                setModelIndex(0);
                setOpenMenu(null);
              }}
            />
          ) : null}
          {openMenu === "model" ? (
            <SelectorMenu
              items={currentModels}
              selectedIndex={modelIndex}
              className="left-[3.5rem] sm:left-[4.5rem]"
              onSelect={(index) => {
                setModelIndex(index);
                setOpenMenu(null);
              }}
            />
          ) : null}
        </div>

        <div className="flex items-center gap-3">
          <Paperclip className="h-4 w-4 [stroke-width:1.6]" />
          <History className="h-4 w-4 [stroke-width:1.6]" />
          <MessageSquarePlus className="h-4 w-4 [stroke-width:1.6]" />
          <Maximize2 className="h-4 w-4 [stroke-width:1.6]" />
          <button
            className="rounded-full bg-orange-500 p-1 transition-colors hover:bg-orange-600"
            type="button"
            aria-label="Send prompt"
          >
            <ArrowUp className="h-3 w-3 [stroke-width:1.6]" />
          </button>
        </div>
      </footer>
    </section>
  );
}

function SelectorButton({
  label,
  isOpen,
  onClick,
}: {
  label: string;
  isOpen: boolean;
  onClick: () => void;
}) {
  return (
    <button
      className="flex max-w-[6.5rem] items-center gap-[0.42rem] border-0 bg-transparent p-0 text-left font-[430] text-[clamp(0.5rem,0.82vw,0.68rem)] text-black"
      type="button"
      aria-expanded={isOpen}
      onClick={onClick}
    >
      <strong className="truncate font-[430]">{label}</strong>
      {isOpen ? (
        <ChevronDown className="h-[0.55rem] w-[0.55rem] shrink-0 text-[#7d7b80] [stroke-width:1.5]" />
      ) : (
        <ChevronUp className="h-[0.55rem] w-[0.55rem] shrink-0 text-[#7d7b80] [stroke-width:1.5]" />
      )}
    </button>
  );
}

function SelectorMenu({
  items,
  selectedIndex,
  className,
  onSelect,
}: {
  items: string[];
  selectedIndex: number;
  className: string;
  onSelect: (index: number) => void;
}) {
  return (
    <div
      className={`absolute top-[calc(100%_+_0.3rem)] z-20 w-44 rounded-lg border border-[#d7d4d0] bg-[#fffdfa] p-1.5] ${className}`}
      role="listbox"
    >
      {items.map((item, index) => (
        <button
          className={`flex w-full items-center justify-between rounded-xl px-2.5 py-1.5 text-left text-xs ${
            selectedIndex === index ? "bg-[#ebe9e6]" : ""
          }`}
          key={item}
          type="button"
          role="option"
          aria-selected={selectedIndex === index}
          onClick={() => onSelect(index)}
        >
          <span className="truncate">{item}</span>
          {selectedIndex === index ? <Check className="h-4 w-4 shrink-0" strokeWidth={1.8} /> : null}
        </button>
      ))}
    </div>
  );
}
