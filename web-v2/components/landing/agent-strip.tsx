import Image from "next/image";
import { agents } from "./data/agents";

export function AgentStrip() {
  return <section className="page-width pt-12 pb-24 md:pt-14 md:pb-32" id="agents" aria-labelledby="agents-title">
    <h2 className="mb-6 text-center text-xs tracking-normal md:text-[13px]" id="agents-title">Works with the agents you already use.</h2>
    <div className="flex flex-wrap gap-2">
      {agents.map(agent => <div className="flex min-h-20 min-w-32 flex-1 items-center justify-center gap-2.5 rounded-sm bg-surface px-4 md:min-w-0 md:py-8" key={agent.id}>
        <Image className="size-6 object-contain brightness-0 grayscale dark:invert" src={`/agents/${agent.id}.svg`} width={24} height={24} alt="" />
        <span className="whitespace-nowrap text-sm tracking-[-0.035em]">{agent.id === "claude" ? "Claude Code" : agent.name}</span>
      </div>)}
    </div>
  </section>;
}
