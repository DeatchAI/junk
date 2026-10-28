import Image from "next/image";
import { Icon } from "./demo/demo-icons";
import styles from "./auto-router.module.css";

export function AutoRouter() {
  return <section className="page-width pb-24 md:pb-32" id="auto-router" aria-labelledby="auto-router-title">
    <div className="mx-auto max-w-xl text-center">
      <p className="mb-5 text-xs text-muted">Auto router</p>
      <h2 className="text-[clamp(2rem,4vw,3rem)] leading-[1.15] tracking-[-0.045em]" id="auto-router-title">A little less choosing.<br />A little more doing.</h2>
      <p className="mx-auto mt-5 max-w-md text-sm leading-6 text-muted">Let Auto router choose an available agent and model for a new task, guided by your preferences. Your existing conversations stay with their original agent.</p>
    </div>
    <div className={`${styles.canvas} mt-10 flex justify-center rounded-sm px-6 py-12 md:mt-14 md:px-12 md:py-16`} aria-label="Example of a task routed to an agent">
      <div className="flex w-full max-w-sm flex-col items-center">
        <div className="w-full rounded-xl bg-background px-5 py-4 text-sm shadow-[0_8px_32px_#0000000a]">
          <p className="mb-2 text-xs text-muted">Your task</p>
          <p>Review the checkout flow and find any bugs.</p>
        </div>
        <span className="h-8 w-px bg-foreground/20" aria-hidden="true" />
        <div className="flex items-center gap-3 rounded-full bg-foreground px-4 py-2.5 text-xs text-background">
          <Icon name="brain" size={16} /><span>Auto router</span>
        </div>
        <span className="h-8 w-px bg-foreground/20" aria-hidden="true" />
        <div className="flex w-full items-center gap-3 rounded-xl bg-background px-5 py-4 shadow-[0_8px_32px_#0000000a]">
          <Image className="size-7 shrink-0 object-contain brightness-0 grayscale dark:invert" src="/agents/codex.svg" width={28} height={28} alt="" />
          <div><p className="text-sm">Codex</p><p className="mt-1 text-xs text-muted">Example selection</p></div>
        </div>
      </div>
    </div>
    <p className="mt-5 text-center text-xs leading-5 text-muted">Optional · Jev routing requires your own TypeSafe API key</p>
  </section>;
}
