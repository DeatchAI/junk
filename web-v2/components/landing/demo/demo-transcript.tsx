import { Icon } from "./demo-icons";
import type { DemoTranscriptPart } from "./demo-data";

export function DemoTranscript({ parts }: { parts: DemoTranscriptPart[] }) {
  return <div data-no-drag="" className="my-3 max-h-[min(40svh,320px)] overflow-y-auto pr-1 text-[14px] leading-[1.5] [overflow-wrap:anywhere] max-[600px]:max-h-[min(18svh,140px)] max-[600px]:text-[13px]">
    {parts.map((part, index) => part.kind === "text"
      ? <p className="my-3 whitespace-pre-wrap" key={index}>{part.text}</p>
      : <details className="my-3 text-[12px] text-[color:var(--app-muted)]" key={index}>
        <summary className="flex cursor-pointer list-none items-center gap-2 [&::-webkit-details-marker]:hidden">
          <Icon name="check" size={13}/><span>{part.summary}</span><Icon name="down" size={12}/>
        </summary>
        <ul className="mt-2 space-y-1 pl-6">{part.details.map(detail => <li key={detail}>{detail}</li>)}</ul>
      </details>)}
  </div>;
}
