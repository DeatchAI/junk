import { useId, useState } from "react";
import { AgentLogo, Icon } from "./demo-icons";
import type { DemoRun } from "./demo-data";

const button = "rounded-full border-0 px-4 py-2 text-[12px] font-medium";

export function DemoAttention({ run, onResolve }: { run: DemoRun; onResolve: (proceed: boolean) => void }) {
  const [choice, setChoice] = useState("");
  const [answer, setAnswer] = useState("");
  const group = useId();
  const attention = run.attention;
  if (!attention) return null;

  return <div className="mb-3 rounded-xl border [border-color:var(--app-line)] [background-color:var(--app-control)] p-3" aria-label={`${run.activity}: ${run.title}`}>
    <div className="mb-4 flex items-start gap-3">
      <span className="mt-0.5"><AgentLogo agent={run.agent} size={18}/></span>
      <div><p className="text-[13px] font-medium">{run.title}</p><p className="mt-1 text-[11px] text-[color:var(--app-muted)]">{run.activity}</p></div>
    </div>
    <p className="mb-3 text-[13px] font-medium leading-[1.4]">{attention.prompt}</p>
    {attention.kind === "approval" ? <>
      <code className="block overflow-x-auto rounded-lg [background-color:var(--app-hover)] px-3 py-2 text-[11px] text-[color:var(--app-fg)]">{attention.command}</code>
      <div className="mt-5 flex flex-wrap items-center gap-2">
        <span className="mr-auto flex items-center gap-1.5 text-[11px] text-[color:var(--app-muted)]"><Icon name="shield" size={13}/>{attention.risk}</span>
        <button type="button" className={`${button} [background-color:var(--app-hover)] text-[color:var(--app-fg)]`} onClick={() => onResolve(false)}>Deny</button>
        <button type="button" className={`${button} [background-color:var(--app-button)] text-[color:var(--app-button-fg)]`} onClick={() => onResolve(true)}>Approve</button>
      </div>
    </> : <>
      <fieldset className="space-y-2" aria-label={attention.prompt}>
        {attention.options.map(option => <label key={option.label} className="flex cursor-pointer items-start gap-2 rounded-lg [background-color:var(--app-hover)] p-2.5">
          <input type="radio" name={group} value={option.label} checked={choice === option.label} onChange={() => setChoice(option.label)}
            className="mt-0.5 size-3.5 shrink-0 appearance-none rounded-full border [border-color:var(--app-muted)] checked:[border-color:var(--app-button)] checked:[background-color:var(--app-button)]"/>
          <span><span className="block text-[12px] font-medium">{option.label}</span><span className="mt-0.5 block text-[11px] leading-[1.35] text-[color:var(--app-muted)]">{option.description}</span></span>
        </label>)}
      </fieldset>
      <textarea aria-label="Your answer" placeholder="Choose above or type your answer" value={answer} onChange={event => setAnswer(event.target.value)}
        className="mt-2 min-h-[44px] w-full resize-y rounded-lg border-0 [background-color:var(--app-hover)] p-2.5 text-[12px] text-[color:var(--app-fg)] placeholder:text-[color:var(--app-muted)]"/>
      <div className="mt-3 flex items-center justify-between gap-2">
        <button type="button" className="border-0 bg-transparent p-1 text-[11px] text-[color:var(--app-muted)]" onClick={() => onResolve(false)}>Cancel task</button>
        <button type="button" className={`${button} [background-color:var(--app-button)] text-[color:var(--app-button-fg)]`} disabled={!choice && !answer.trim()} onClick={() => onResolve(true)}>Continue</button>
      </div>
    </>}
  </div>;
}
