import Image from "next/image";
import {
  AppWindow,
  ArrowUpRight,
  Bot,
  Check,
  CheckCircle2,
  ChevronRight,
  CircleCheckBig,
  Code2,
  Command,
  FileCode2,
  Fingerprint,
  KeyRound,
  LockKeyhole,
  MousePointer2,
  Play,
  Search,
  Server,
  ShieldCheck,
  Workflow,
  Zap,
} from "lucide-react";

const featureLinks = [
  { number: "01", label: "Your agents", href: "#agents" },
  { number: "02", label: "Browser", href: "#browser" },
  { number: "03", label: "macOS", href: "#macos" },
  { number: "04", label: "Coding", href: "#coding" },
  { number: "05", label: "Secrets", href: "#security" },
  { number: "06", label: "Integrations", href: "#integrations" },
  { number: "07", label: "Workflows", href: "#workflows" },
  { number: "08", label: "Quick Actions", href: "#quick-actions" },
];

const agents = [
  { name: "Codex", detail: "Found on this Mac", glyph: "C" },
  { name: "Claude Code", detail: "Found on this Mac", glyph: "C" },
  { name: "Grok", detail: "Found on this Mac", glyph: "G" },
];

const integrationIcons = [
  { src: "/icons/githubApp.webp", alt: "GitHub" },
  { src: "/icons/slackApp.webp", alt: "Slack" },
  { src: "/icons/notionApp.webp", alt: "Notion" },
  { src: "/icons/gmailApp.webp", alt: "Gmail" },
  { src: "/icons/googlecalendarApp.png", alt: "Google Calendar" },
  { src: "/icons/linearApp.webp", alt: "Linear" },
  { src: "/icons/figmaApp.webp", alt: "Figma" },
  { src: "/icons/googleDocsApp.webp", alt: "Google Docs" },
  { src: "/icons/teamsApp.webp", alt: "Microsoft Teams" },
  { src: "/icons/outlookApp.webp", alt: "Outlook" },
  { src: "/icons/googlemapsApp.png", alt: "Google Maps" },
  { src: "/icons/imessageApp.webp", alt: "Messages" },
];

const workflows = [
  {
    title: "Morning operations brief",
    prompt: "Review renewals, calendar, and open blockers.",
    tools: "3 capabilities",
  },
  {
    title: "Triage failed CI",
    prompt: "Inspect the run and draft an evidence-backed note.",
    tools: "Browser + GitHub",
  },
  {
    title: "Prepare discovery call",
    prompt: "Build a source-backed brief from connected context.",
    tools: "4 capabilities",
  },
];

function FeatureLabel({ number, children }: { number: string; children: React.ReactNode }) {
  return (
    <p className="m-0 inline-flex items-center gap-[0.55rem] text-xs font-semibold uppercase leading-none tracking-[0.12em] [&>span]:text-[#ff7900]">
      <span>{number}</span>
      {children}
    </p>
  );
}

function ProductChip({ children }: { children: React.ReactNode }) {
  return (
    <span className="inline-flex min-h-8 items-center gap-[0.45rem] rounded-full border border-current px-[0.7rem] py-[0.45rem] text-[0.72rem] font-medium leading-none opacity-75">
      <Check className="size-3 stroke-[2.1]" aria-hidden="true" />
      {children}
    </span>
  );
}

export default function FeatureShowcase() {
  return (
    <>
      <section
        id="features"
        className="relative overflow-hidden bg-[radial-gradient(circle_at_9%_4%,rgba(255,121,0,0.08),transparent_25rem)] bg-[#f4f1eb] px-[clamp(1rem,3vw,2rem)] py-[clamp(7rem,11vw,10.5rem)] text-[#11100f] before:pointer-events-none before:absolute before:inset-0 before:bg-[linear-gradient(rgba(17,16,15,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(17,16,15,0.025)_1px,transparent_1px)] before:bg-[size:48px_48px] before:content-[''] before:[mask-image:linear-gradient(to_bottom,black,transparent_38%)] max-[700px]:pt-[5.5rem]"
        aria-labelledby="features-heading"
      >
        <div className="mx-auto w-full max-w-[1180px]">
          <header className="relative z-[1] flex flex-col items-center">
            <h2 id="features-heading" className="sick mt-[clamp(1.5rem,2.7vw,2.5rem)] max-w-[1080px] text-center
            text-[clamp(4rem,9.7vw,4.7rem)] font-normal leading-[0.84] max-[700px]:text-[clamp(3.55rem,18vw,5.8rem)] max-[700px]:leading-[0.86]">
              You have the agents.
              <br />
              Now give them your Mac.
            </h2>
            <p className="mt-[clamp(2.25rem,5vw,4.75rem)] ml-auto w-full max-w-[650px] text-center text-[clamp(1.1rem,1.9vw,1.55rem)] font-normal leading-[1.35] tracking-[-0.02em] text-[rgba(17,16,15,0.64)] max-[700px]:ml-0 max-[700px]:text-[1.05rem]">
              Use the AI already signed in on your computer, give it browser and
              macOS capabilities, then let every task disappear into the notch
              while it works.
            </p>
          </header>

          <nav className="relative z-[1] mt-[clamp(4rem,8vw,7rem)] grid grid-cols-4 border-t border-l border-[rgba(17,16,15,0.18)] [&_a]:grid [&_a]:min-h-[5.5rem] [&_a]:grid-cols-[auto_minmax(0,1fr)_auto] [&_a]:items-center [&_a]:gap-[0.8rem] [&_a]:border-r [&_a]:border-b [&_a]:border-[rgba(17,16,15,0.14)] [&_a]:p-[1rem_1.1rem] [&_a]:text-inherit [&_a]:no-underline [&_a]:transition-colors [&_a]:duration-200 [&_a:hover]:bg-[#11100f] [&_a:hover]:text-white [&_a:focus-visible]:bg-[#11100f] [&_a:focus-visible]:text-white [&_a:focus-visible]:outline-none [&_a>span]:text-[0.68rem] [&_a>span]:font-semibold [&_a>span]:text-[#ff7900] [&_a>strong]:overflow-hidden [&_a>strong]:text-ellipsis [&_a>strong]:whitespace-nowrap [&_a>strong]:text-[0.88rem] [&_a>strong]:font-medium [&_a>svg]:size-[0.9rem] [&_a>svg]:opacity-45 max-[1000px]:grid-cols-2 max-[700px]:[&_a]:min-h-[4.5rem] max-[700px]:[&_a]:grid-cols-[auto_minmax(0,1fr)] max-[700px]:[&_a]:p-[0.85rem] max-[700px]:[&_a>strong]:text-[0.76rem] max-[700px]:[&_a>svg]:hidden" aria-label="Feature index">
            {featureLinks.map((feature) => (
              <a href={feature.href} key={feature.number}>
                <span>{feature.number}</span>
                <strong>{feature.label}</strong>
                <ChevronRight aria-hidden="true" />
              </a>
            ))}
          </nav>

          <article id="agents" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] mt-[clamp(4rem,7vw,6.5rem)] grid min-h-[690px] grid-cols-[minmax(0,0.85fr)_minmax(0,1.15fr)] bg-[#080808] p-[clamp(2rem,5vw,4.5rem)] text-white after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:border after:border-white/10 after:content-[''] [&>div:first-child]:self-center [&>div:first-child_p]:!text-white/60 max-[1000px]:grid-cols-1 max-[1000px]:gap-8 max-[700px]:min-h-0 max-[700px]:p-6">
            <div className="relative z-[2] flex flex-col items-start [&>small]:mt-6 [&>small]:block [&>small]:text-[0.74rem] [&>small]:leading-[1.35] [&>small]:text-current [&>small]:opacity-50">
              <FeatureLabel number="01">Your agents</FeatureLabel>
              <h3>Use the AI you already pay for.</h3>
              <p>
                Run your signed-in Codex, Claude Code, or Grok CLI. No Detach
                credits, no second model plan, and nothing routed through a
                hosted Detach model.
              </p>
              <div className="mt-8 flex flex-wrap gap-[0.55rem]">
                <ProductChip>Local CLI agents</ProductChip>
                <ProductChip>Your provider account</ProductChip>
              </div>
              <small>Install and sign in to the corresponding CLI once.</small>
            </div>

            <div className="relative grid min-h-[530px] items-center justify-items-end max-[1000px]:mx-auto max-[1000px]:w-full max-[1000px]:max-w-[680px] max-[1000px]:justify-items-center max-[700px]:min-h-[470px]" aria-hidden="true">
              <div className="absolute aspect-square w-[78%] translate-x-[9%] translate-y-[2%] rounded-full bg-[#ff7900] opacity-[0.72] blur-[4rem]" />
              <div className="relative w-full max-w-[510px] rotate-[1.2deg] rounded-[1.7rem] border border-white/15 bg-[rgba(13,13,14,0.93)] p-[1.05rem] shadow-[0_2.5rem_6rem_rgba(0,0,0,0.42)] backdrop-blur-[28px] max-[700px]:rotate-0">
                <div className="flex items-center gap-[0.8rem] p-[0.4rem_0.35rem_1rem] [&>span]:grid [&>span]:size-[2.6rem] [&>span]:shrink-0 [&>span]:place-items-center [&>span]:rounded-[0.85rem] [&>span]:bg-white/[0.08] [&_svg]:size-[1.15rem] [&_svg]:stroke-[1.6] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.9rem] [&_strong]:font-medium [&_small]:mt-[0.16rem] [&_small]:text-[0.7rem] [&_small]:font-normal [&_small]:text-white/45">
                  <span>
                    <Bot />
                  </span>
                  <div>
                    <strong>Your subscriptions, your agents.</strong>
                    <small>Choose the agent for this task.</small>
                  </div>
                </div>
                <div className="flex flex-col gap-2">
                  {agents.map((agent, index) => (
                    <div
                      className={`grid min-h-[4.5rem] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl border p-[0.7rem] [&>span:nth-child(2)]:flex [&>span:nth-child(2)]:min-w-0 [&>span:nth-child(2)]:flex-col [&>span:nth-child(2)]:items-start [&_strong]:text-[0.82rem] [&_strong]:font-medium [&_small]:mt-[0.16rem] [&_small]:text-[0.7rem] [&_small]:font-normal [&_small]:text-white/45 [&>svg]:size-[1.05rem] [&>svg]:stroke-[1.8] [&>svg]:text-[#38df68] ${
                        index === 0 ? "border-[#ff7900]/50 bg-[#ff7900]/10" : "border-transparent bg-white/[0.035]"
                      }`}
                      key={agent.name}
                    >
                      <span className="grid size-[2.6rem] place-items-center rounded-[0.85rem] bg-white text-[0.9rem] font-bold text-[#0b0b0b]">{agent.glyph}</span>
                      <span>
                        <strong>{agent.name}</strong>
                        <small>{agent.detail}</small>
                      </span>
                      <CircleCheckBig />
                    </div>
                  ))}
                </div>
                <div className="mt-[0.8rem] flex items-center gap-2 px-3 pt-[0.85rem] pb-[0.2rem] text-[0.67rem] text-white/45 [&_svg]:size-[0.9rem] [&_svg]:text-[#38df68]">
                  <ShieldCheck />
                  Nothing is routed through a Detach model
                </div>
              </div>
            </div>
          </article>

          <div className="mt-[clamp(1rem,2vw,1.5rem)] grid grid-cols-2 gap-[clamp(1rem,2vw,1.5rem)] max-[1000px]:grid-cols-1">
            <article id="browser" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] min-h-[710px] bg-[#fefdfb] p-[clamp(1.7rem,3.7vw,3.1rem)] max-[1000px]:min-h-[700px] max-[700px]:min-h-0 max-[700px]:p-6">
              <div className="relative z-[2] flex flex-col items-start [&_h3]:mt-[1.2rem] [&_h3]:text-[clamp(2.4rem,4vw,3.9rem)] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)]">
                <FeatureLabel number="02">Browser automation</FeatureLabel>
                <h3>Automate the browser you already use.</h3>
                <p>
                  Let agents research, navigate, click, type, and complete routine
                  web work inside your signed-in Chrome profile.
                </p>
              </div>

              <div className="absolute right-[clamp(1rem,3vw,2.25rem)] bottom-[clamp(1rem,3vw,2.25rem)] left-[clamp(1rem,3vw,2.25rem)] h-[330px] overflow-hidden rounded-[1.35rem] border border-[rgba(17,16,15,0.15)] bg-white shadow-[0_1.5rem_3rem_rgba(25,18,12,0.12)] max-[700px]:relative max-[700px]:right-auto max-[700px]:bottom-auto max-[700px]:left-auto max-[700px]:mt-8 max-[700px]:h-[300px]" aria-hidden="true">
                <div className="grid h-[2.65rem] grid-cols-[74px_minmax(0,1fr)_74px] items-center border-b border-black/10 bg-[#f3f0eb] px-[0.7rem]">
                  <div className="flex gap-[0.3rem] [&_i]:size-[0.52rem] [&_i]:rounded-full [&_i]:bg-[#ff5f57] [&_i:nth-child(2)]:bg-[#febc2e] [&_i:nth-child(3)]:bg-[#28c840]">
                    <i />
                    <i />
                    <i />
                  </div>
                  <div className="flex min-w-0 items-center justify-center gap-[0.35rem] overflow-hidden text-ellipsis whitespace-nowrap text-[0.62rem] text-black/50 [&_svg]:size-[0.68rem] [&_svg]:stroke-[1.8]">
                    <LockKeyhole />
                    app.acme.com/renewals
                  </div>
                </div>
                <div className="grid h-[calc(100%-2.65rem)] grid-cols-[25%_minmax(0,1fr)]">
                  <div className="flex flex-col gap-3 border-r border-black/[0.08] bg-[#faf8f5] px-[0.8rem] py-[1.2rem] [&_span]:h-[0.45rem] [&_span]:rounded-full [&_span]:bg-[#dedad3] [&_span:nth-child(2)]:w-[72%] [&_span:nth-child(2)]:bg-[#ffb06a] [&_span:nth-child(3)]:w-[84%]">
                    <span />
                    <span />
                    <span />
                    <span />
                  </div>
                  <div className="p-[1.2rem_1rem]">
                    <div className="flex flex-col gap-[0.45rem] [&_span]:h-[0.6rem] [&_span]:w-1/2 [&_span]:rounded-full [&_span]:bg-[#201f1d] [&_span:last-child]:h-[0.35rem] [&_span:last-child]:w-[78%] [&_span:last-child]:bg-[#d8d4ce]">
                      <span />
                      <span />
                    </div>
                    <div className="mt-4 flex flex-col rounded-[0.8rem] border border-[#ebe7e1] [&>div]:grid [&>div]:min-h-[2.6rem] [&>div]:grid-cols-[auto_minmax(0,1fr)_auto] [&>div]:items-center [&>div]:gap-[0.55rem] [&>div]:border-b [&>div]:border-[#ebe7e1] [&>div]:px-[0.65rem] [&>div:last-child]:border-b-0 [&_i]:grid [&_i]:size-[1.35rem] [&_i]:place-items-center [&_i]:rounded-[0.4rem] [&_i]:bg-[#f1ede7] [&_i]:text-[0.55rem] [&_i]:not-italic [&_i]:font-semibold [&_span]:text-[0.62rem] [&_em]:text-[0.62rem] [&_em]:not-italic [&_em]:text-[#2a9750]">
                      {["Figma", "Linear", "Notion"].map((name, index) => (
                        <div key={name}>
                          <i>{name.slice(0, 1)}</i>
                          <span>{name}</span>
                          <em>{index === 1 ? "Review" : "Active"}</em>
                        </div>
                      ))}
                    </div>
                  </div>
                </div>
                <div className="absolute right-[0.7rem] bottom-[0.8rem] grid min-h-[4.2rem] w-[min(88%,320px)] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.65rem] rounded-2xl bg-[#101011] p-3 text-white shadow-[0_1rem_2rem_rgba(0,0,0,0.25)] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:overflow-hidden [&_strong]:text-ellipsis [&_strong]:whitespace-nowrap [&_strong]:text-[0.68rem] [&_strong]:font-medium [&_small]:mt-[0.15rem] [&_small]:text-[0.58rem] [&_small]:text-white/45 [&>svg]:size-[0.9rem] [&>svg]:text-[#ff7900]">
                  <span className="size-[0.55rem] animate-pulse rounded-full bg-[#ff7900] shadow-[0_0_0_0.32rem_rgba(255,121,0,0.14)] motion-reduce:animate-none" />
                  <div>
                    <strong>Reviewing renewal terms</strong>
                    <small>Using browser.snapshot</small>
                  </div>
                  <MousePointer2 />
                </div>
              </div>
            </article>

            <article id="macos" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] min-h-[710px] bg-[#ffd5b0] p-[clamp(1.7rem,3.7vw,3.1rem)] max-[1000px]:min-h-[700px] max-[700px]:min-h-0 max-[700px]:p-6">
              <div className="relative z-[2] flex flex-col items-start [&_h3]:mt-[1.2rem] [&_h3]:text-[clamp(2.4rem,4vw,3.9rem)] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)]">
                <FeatureLabel number="03">macOS automation</FeatureLabel>
                <h3>Give your agents hands on macOS.</h3>
                <p>
                  Open apps, inspect windows, click controls, type, use shortcuts,
                  and move work between native apps.
                </p>
              </div>

              <div className="absolute right-[clamp(1rem,3vw,2.25rem)] bottom-[clamp(1rem,3vw,2.25rem)] left-[clamp(1rem,3vw,2.25rem)] h-[330px] overflow-hidden rounded-[1.35rem] border border-black/15 bg-white/60 p-4 shadow-[inset_0_1px_0_rgba(255,255,255,0.65)] backdrop-blur-[22px] max-[700px]:relative max-[700px]:right-auto max-[700px]:bottom-auto max-[700px]:left-auto max-[700px]:mt-8 max-[700px]:h-[300px]" aria-hidden="true">
                <div className="flex items-center justify-between text-[0.7rem] font-semibold text-[#24201c] [&_span]:inline-flex [&_span]:items-center [&_span]:gap-[0.4rem] [&_em]:inline-flex [&_em]:items-center [&_em]:gap-[0.4rem] [&_em]:text-[0.6rem] [&_em]:font-medium [&_em]:not-italic [&_em]:text-[#278848] [&_em]:before:size-[0.4rem] [&_em]:before:rounded-full [&_em]:before:bg-[#38c968] [&_em]:before:content-[''] [&_svg]:size-[0.9rem]">
                  <span>
                    <AppWindow /> macOS bridge
                  </span>
                  <em>Connected</em>
                </div>
                <div className="mt-4 flex gap-[0.65rem] [&>span]:grid [&>span]:size-[2.55rem] [&>span]:place-items-center [&>span]:rounded-xl [&>span]:border [&>span]:border-black/[0.08] [&>span]:bg-white/60 [&>span]:shadow-[0_0.45rem_1rem_rgba(68,44,23,0.08)] [&_img]:size-7 [&_img]:object-contain max-[700px]:gap-[0.45rem] max-[700px]:[&>span]:size-[2.15rem] max-[700px]:[&_img]:size-[1.45rem]">
                  {integrationIcons.slice(1, 6).map((icon) => (
                    <span key={icon.alt}>
                      <Image src={icon.src} alt="" width={46} height={46} />
                    </span>
                  ))}
                </div>
                <div className="mt-4 flex flex-col border-t border-black/10 [&>div]:grid [&>div]:min-h-[2.45rem] [&>div]:grid-cols-[auto_minmax(0,1fr)_auto] [&>div]:items-center [&>div]:gap-[0.55rem] [&>div]:border-b [&>div]:border-black/[0.08] [&>div>span]:grid [&>div>span]:size-[1.15rem] [&>div>span]:place-items-center [&>div>span]:rounded-full [&>div>span]:bg-black/[0.08] [&>div>span]:text-[0.52rem] [&>div>span]:font-semibold [&_strong]:text-[0.62rem] [&_strong]:font-medium [&_small]:text-[0.62rem] [&_small]:font-medium [&_small]:text-[#3c9759]">
                  {[
                    ["Open Calendar", "Completed"],
                    ["Create the review block", "Completed"],
                    ["Draft the Slack update", "Working"],
                  ].map(([title, status], index) => (
                    <div key={title}>
                      <span>{index + 1}</span>
                      <strong>{title}</strong>
                      <small className={status === "Working" ? "!text-[#d36300]" : ""}>
                        {status}
                      </small>
                    </div>
                  ))}
                </div>
                <div className="absolute right-3 bottom-[0.7rem] left-3 flex min-h-[3.2rem] items-center gap-[0.35rem] rounded-[0.9rem] bg-[#101011] px-3 py-[0.65rem] text-[0.65rem] text-white/80 shadow-[0_1rem_2rem_rgba(58,32,13,0.18)] [&_span]:text-[#ff7900] [&_svg]:ml-auto [&_svg]:size-[0.85rem]">
                  <span>@macOS</span> Move my review block and tell the team.
                  <ArrowUpRight />
                </div>
              </div>
            </article>
          </div>

          <article id="coding" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] mt-[clamp(1rem,2vw,1.5rem)] grid min-h-[720px] grid-cols-[minmax(0,0.82fr)_minmax(0,1.18fr)] bg-[#0b0b0c] p-[clamp(2rem,5vw,4.5rem)] text-white after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:border after:border-white/10 after:content-[''] [&>div:first-child]:self-center [&>div:first-child_p]:!text-white/60 max-[1000px]:grid-cols-1 max-[1000px]:gap-8 max-[700px]:min-h-0 max-[700px]:p-6">
            <div className="relative z-[2] flex flex-col items-start [&>small]:mt-6 [&>small]:block [&>small]:text-[0.74rem] [&>small]:leading-[1.35] [&>small]:text-current [&>small]:opacity-50">
              <FeatureLabel number="04">Detached coding</FeatureLabel>
              <h3>Code, then get out of the way.</h3>
              <p>
                Attach a file or folder, send the task, close the composer, and
                follow live progress from the notch. Detach keeps working without
                turning your desktop into another IDE.
              </p>
              <div className="mt-8 flex flex-wrap gap-[0.55rem]">
                <ProductChip>File and folder context</ProductChip>
                <ProductChip>Live task activity</ProductChip>
              </div>
            </div>

            <div className="relative min-h-[540px] max-[1000px]:mx-auto max-[1000px]:w-full max-[1000px]:max-w-[680px] max-[700px]:min-h-[470px]" aria-hidden="true">
              <div className="absolute top-0 left-1/2 z-[3] grid min-h-[4.65rem] w-[min(86%,410px)] -translate-x-1/2 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.65rem] rounded-b-[1.5rem] bg-black px-4 py-[0.8rem] shadow-[0_1rem_2.5rem_rgba(0,0,0,0.5)] [&_img]:size-[1.45rem] [&>span]:flex [&>span]:min-w-0 [&>span]:flex-col [&_strong]:overflow-hidden [&_strong]:text-ellipsis [&_strong]:whitespace-nowrap [&_strong]:text-[0.68rem] [&_strong]:font-medium [&_strong]:text-white [&_small]:mt-[0.12rem] [&_small]:text-[0.58rem] [&_small]:text-white/45 [&>i]:size-2 [&>i]:animate-pulse [&>i]:rounded-full [&>i]:bg-[#ff7900] [&>i]:shadow-[0_0_0_0.28rem_rgba(255,121,0,0.12)] motion-reduce:[&>i]:animate-none">
                <Image src="/icon.svg" alt="" width={22} height={22} />
                <span>
                  <strong>Review checkout.ts</strong>
                  <small>Running tests</small>
                </span>
                <i />
              </div>
              <div className="absolute top-[4.2rem] right-0 left-0 min-h-[385px] overflow-hidden rounded-[1.6rem] border border-white/15 bg-[#151517] shadow-[0_2rem_4rem_rgba(0,0,0,0.28)] [&_header]:flex [&_header]:h-[3.25rem] [&_header]:items-center [&_header]:justify-between [&_header]:border-b [&_header]:border-white/[0.08] [&_header]:px-4 [&_header]:text-[0.65rem] [&_header]:text-white/75 [&_header_span]:inline-flex [&_header_span]:items-center [&_header_span]:gap-[0.45rem] [&_header_svg]:size-[0.9rem] [&_header_svg]:text-[#ff7900] [&_header_em]:text-[0.58rem] [&_header_em]:not-italic [&_header_em]:text-[#38df68]">
                <header>
                  <span>
                    <FileCode2 /> checkout.ts
                  </span>
                  <em>2 changes</em>
                </header>
                <div className="flex flex-col overflow-hidden py-[1.2rem] font-mono [&>span]:grid [&>span]:min-h-8 [&>span]:grid-cols-[2.1rem_minmax(0,1fr)] [&>span]:items-center [&>span]:whitespace-nowrap [&>span]:px-[0.9rem] [&>span]:text-[clamp(0.53rem,0.7vw,0.66rem)] [&>span]:text-white/65 [&_i]:not-italic [&_i]:text-white/20 max-[700px]:[&>span]:text-[0.46rem]">
                  <span><i>41</i> const reservation = await reserveCredits(input)</span>
                  <span className="!bg-[rgba(255,70,83,0.11)] !text-[rgba(255,168,174,0.82)]"><i>42</i> await generateAsset(input)</span>
                  <span className="!bg-[rgba(56,223,104,0.09)] !text-[rgba(161,244,185,0.82)]"><i>42</i> try &#123;</span>
                  <span className="!bg-[rgba(56,223,104,0.09)] !text-[rgba(161,244,185,0.82)]"><i>43</i> &nbsp; await generateAsset(input)</span>
                  <span className="!bg-[rgba(56,223,104,0.09)] !text-[rgba(161,244,185,0.82)]"><i>44</i> &#125; catch (error) &#123;</span>
                  <span className="!bg-[rgba(56,223,104,0.09)] !text-[rgba(161,244,185,0.82)]"><i>45</i> &nbsp; await refundReservation(reservation)</span>
                  <span><i>46</i> &#125;</span>
                </div>
              </div>
              <div className="absolute right-[-1rem] bottom-0 z-[4] min-h-[7.9rem] w-[min(84%,440px)] -rotate-1 rounded-[1.3rem] border border-white/15 bg-[rgba(12,12,13,0.97)] p-4 text-[0.75rem] leading-normal text-white/70 shadow-[0_1.8rem_4rem_rgba(0,0,0,0.48)] [&>span]:mr-[0.2rem] [&>span]:text-[#ff7900] [&>div]:absolute [&>div]:right-[0.9rem] [&>div]:bottom-[0.8rem] [&>div]:left-[0.9rem] [&>div]:flex [&>div]:items-center [&>div]:gap-[0.6rem] [&>div]:text-white/50 [&>div>strong]:text-[0.6rem] [&>div>strong]:font-medium [&>div>strong]:text-white/80 [&>div>svg]:size-[0.8rem] [&>div>i]:ml-auto [&>div>i]:grid [&>div>i]:size-[1.65rem] [&>div>i]:place-items-center [&>div>i]:rounded-full [&>div>i]:bg-[#ff7900] [&>div>i]:text-[#130b04] [&>div>i_svg]:size-[0.8rem] max-[700px]:right-0 max-[700px]:w-[92%]">
                <span>/code-review</span>
                Check the credit reservation path and add the missing rollback.
                <div>
                  <strong>Codex</strong>
                  <Command />
                  <i><ChevronRight /></i>
                </div>
              </div>
            </div>
          </article>

          <article id="security" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] mt-[clamp(1rem,2vw,1.5rem)] grid min-h-[720px] grid-cols-[minmax(0,0.82fr)_minmax(0,1.18fr)] bg-[#ffd7b4] p-[clamp(2rem,5vw,4.5rem)] [&>div:first-child]:self-center max-[1000px]:grid-cols-1 max-[1000px]:gap-8 max-[700px]:min-h-0 max-[700px]:p-6">
            <div className="relative z-[2] flex flex-col items-start [&>small]:mt-6 [&>small]:block [&>small]:text-[0.74rem] [&>small]:leading-[1.35] [&>small]:text-current [&>small]:opacity-50">
              <FeatureLabel number="05">Secrets</FeatureLabel>
              <h3>Sign in without handing over the password.</h3>
              <p>
                Credentials stay in macOS Keychain. Touch ID fills verified browser
                login fields only after Touch ID, while the agent never receives
                the password value.
              </p>
              <div className="mt-8 flex flex-wrap gap-[0.55rem]">
                <ProductChip>macOS Keychain</ProductChip>
                <ProductChip>Touch ID every use</ProductChip>
                <ProductChip>Origin verified</ProductChip>
              </div>
              <small>Secure fill currently supports browser logins.</small>
            </div>

            <div className="relative min-h-[520px] max-[1000px]:mx-auto max-[1000px]:w-full max-[1000px]:max-w-[680px] max-[700px]:min-h-[470px]" aria-hidden="true">
              <div className="absolute top-6 right-0 min-h-[330px] w-[min(90%,500px)] rounded-[1.6rem] border border-black/15 bg-white/60 p-[1.2rem] text-[#171513] shadow-[0_2rem_4rem_rgba(75,40,11,0.14)] backdrop-blur-[30px] [&>p]:mt-[2.6rem] [&>p]:text-[0.62rem] [&>p]:font-medium [&>p]:uppercase [&>p]:tracking-[0.08em] [&>p]:text-black/45 max-[700px]:w-full">
                <div className="flex items-center justify-between [&_span]:inline-flex [&_span]:items-center [&_span]:gap-[0.45rem] [&_span]:text-[0.76rem] [&_span]:font-semibold [&_svg]:size-4 [&_svg]:text-[#1d8a46]">
                  <span><KeyRound /> Secrets</span>
                  <ShieldCheck />
                </div>
                <p>Saved credentials</p>
                <div className="mt-3 grid min-h-20 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl border border-black/10 bg-white/60 p-[0.8rem] [&>span]:grid [&>span]:size-10 [&>span]:place-items-center [&>span]:rounded-[0.8rem] [&>span]:bg-black/[0.07] [&>span_svg]:size-[1.05rem] [&>span_svg]:text-[#258d49] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.72rem] [&_strong]:font-semibold [&_small]:mt-[0.2rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.58rem] [&_small]:text-black/45 [&_em]:text-[0.58rem] [&_em]:font-semibold [&_em]:not-italic [&_em]:text-[#268a48]">
                  <span><LockKeyhole /></span>
                  <div>
                    <strong>GitHub Work</strong>
                    <small>r••••@detach.app · github.com</small>
                  </div>
                  <em>Keychain</em>
                </div>
                <div className="mt-[0.85rem] flex items-center gap-[0.45rem] text-[0.58rem] text-black/50 [&_svg]:size-[0.82rem]">
                  <Fingerprint /> Device authentication required before every use
                </div>
              </div>

              <div className="absolute right-[-1rem] bottom-[2.8rem] left-0 grid min-h-[5.5rem] -rotate-1 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-[1.25rem] border border-white/15 bg-[#080808] px-[1.2rem] py-4 text-white shadow-[0_2rem_4rem_rgba(75,39,10,0.25)] [&>svg]:size-[1.45rem] [&>svg]:stroke-[1.5] [&>span]:flex [&>span]:min-w-0 [&>span]:flex-col [&_strong]:text-[0.72rem] [&_strong]:font-medium [&_small]:mt-[0.15rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.6rem] [&_small]:text-white/45 [&_em]:whitespace-nowrap [&_em]:text-[0.6rem] [&_em]:not-italic [&_em]:text-[#38df68] max-[700px]:right-0 max-[700px]:bottom-4 max-[700px]:[&_em]:hidden">
                <Fingerprint />
                <span>
                  <strong>Touch ID required</strong>
                  <small>Use GitHub Work for github.com</small>
                </span>
                <em>Credential hidden</em>
              </div>
            </div>
          </article>

          <article id="integrations" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] mt-[clamp(1rem,2vw,1.5rem)] grid grid-cols-[minmax(0,0.72fr)_minmax(0,1.28fr)] bg-[#080808] p-[clamp(2rem,5vw,4.5rem)] text-white after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:border after:border-white/10 after:content-[''] [&>div:first-child_p]:!text-white/60 max-[1000px]:grid-cols-1 max-[1000px]:gap-8 max-[700px]:min-h-0 max-[700px]:p-6">
            <div className="relative z-[2] flex flex-col items-start self-center">
              <FeatureLabel number="06">MCP + integrations</FeatureLabel>
              <h3>800+ integrations. Authenticate and go.</h3>
              <p>
                Connect the apps you already use, attach only the tools a task
                needs, or bring your own HTTP, SSE, or stdio MCP server.
              </p>
            </div>

            <div className="relative min-h-[540px] rounded-[1.8rem] border border-white/10 bg-[radial-gradient(circle_at_50%_40%,rgba(255,121,0,0.22),transparent_38%)] bg-white/[0.025] p-[1.2rem] max-[1000px]:mx-auto max-[1000px]:w-full max-[1000px]:max-w-[680px] max-[700px]:min-h-[520px]" aria-hidden="true">
              <div className="grid grid-cols-4 gap-[0.85rem]">
                {integrationIcons.map((icon) => (
                  <span className="grid aspect-square place-items-center rounded-[1.15rem] border border-white/10 bg-white/[0.06] shadow-[inset_0_1px_0_rgba(255,255,255,0.08)] [&:nth-child(3n+1)]:translate-y-2 [&:nth-child(3n+2)]:-translate-y-[0.3rem] [&_img]:size-[clamp(1.8rem,3.3vw,2.65rem)] [&_img]:object-contain [&_img]:saturate-[0.84]" key={icon.alt}>
                    <Image src={icon.src} alt="" width={44} height={44} />
                  </span>
                ))}
              </div>
              <div className="absolute top-[43%] left-1/2 flex aspect-square w-48 -translate-x-1/2 -translate-y-1/2 flex-col items-center justify-center rounded-full border border-white/15 bg-[rgba(8,8,8,0.92)] shadow-[0_0_5rem_rgba(255,121,0,0.35)] backdrop-blur-[20px] [&_strong]:text-[4.2rem] [&_strong]:font-normal [&_strong]:leading-[0.9] [&_strong]:tracking-[-0.03em] [&_span]:mt-2 [&_span]:text-[0.62rem] [&_span]:text-white/45 max-[700px]:w-[9.5rem] max-[700px]:[&_strong]:text-[3.3rem]">
                <strong className="sick">800+</strong>
                <span>ready-to-connect apps</span>
              </div>
              <div className="absolute right-[1.2rem] bottom-[4.75rem] left-[1.2rem] grid min-h-[3.2rem] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.6rem] rounded-[0.9rem] border border-white/10 bg-black/75 px-[0.85rem] text-[0.66rem] text-white/40 backdrop-blur-[20px] [&_svg]:size-[0.9rem] [&_kbd]:rounded-[0.35rem] [&_kbd]:border [&_kbd]:border-white/10 [&_kbd]:px-[0.38rem] [&_kbd]:py-[0.24rem] [&_kbd]:font-[inherit] [&_kbd]:text-[0.55rem] [&_kbd]:text-white/55">
                <Search />
                <span>Search integrations</span>
                <kbd>⌘ K</kbd>
              </div>
              <div className="absolute right-[1.2rem] bottom-4 left-[1.2rem] flex items-center gap-[0.8rem] text-[0.58rem] text-white/50 [&_span]:inline-flex [&_span]:items-center [&_span]:gap-[0.35rem] [&_svg]:size-3 [&_span:nth-child(2)_svg]:text-[#38df68] [&_button]:ml-auto [&_button]:min-h-[1.9rem] [&_button]:rounded-full [&_button]:border-0 [&_button]:bg-white [&_button]:px-[0.7rem] [&_button]:text-[0.56rem] [&_button]:font-semibold [&_button]:text-[#111] max-[700px]:[&_span:nth-child(2)]:hidden">
                <span><Server /> Built-in</span>
                <span><CheckCircle2 /> Authenticated</span>
                <button type="button" tabIndex={-1}>Attach to task</button>
              </div>
            </div>
          </article>
          <div className="mt-[clamp(1rem,2vw,1.5rem)] grid grid-cols-2 gap-[clamp(1rem,2vw,1.5rem)] max-[1000px]:grid-cols-1">
            <article id="workflows" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] min-h-[710px] bg-[#fffdfa] p-[clamp(1.7rem,3.7vw,3.1rem)] max-[1000px]:min-h-[700px] max-[700px]:min-h-0 max-[700px]:p-6">
              <div className="relative z-[2] flex flex-col items-start [&_h3]:mt-[1.2rem] [&_h3]:text-[clamp(2.4rem,4vw,3.9rem)] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)]">
                <FeatureLabel number="07">Workflows</FeatureLabel>
                <h3>Make repeat work one click.</h3>
                <p>
                  Save a reusable instruction with the exact capabilities it
                  needs, then launch it as a fresh detached task.
                </p>
              </div>
              <div className="absolute right-[clamp(1rem,3vw,2.25rem)] bottom-[clamp(1rem,3vw,2.25rem)] left-[clamp(1rem,3vw,2.25rem)] flex flex-col gap-[0.65rem] max-[700px]:relative max-[700px]:right-auto max-[700px]:bottom-auto max-[700px]:left-auto max-[700px]:mt-8" aria-hidden="true">
                {workflows.map((workflow, index) => (
                  <div className="relative grid min-h-24 grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 overflow-hidden rounded-[1.05rem] border border-black/10 bg-white p-[0.8rem] [&>span]:grid [&>span]:size-10 [&>span]:place-items-center [&>span]:rounded-[0.8rem] [&>span]:bg-[#f1ede7] [&>span_svg]:size-[1.05rem] [&>span_svg]:stroke-[1.6] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.68rem] [&_strong]:font-semibold [&_small]:mt-[0.16rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.57rem] [&_small]:text-black/50 [&_em]:mt-[0.42rem] [&_em]:text-[0.54rem] [&_em]:font-medium [&_em]:not-italic [&_em]:text-[#c85d00] [&_button]:grid [&_button]:size-8 [&_button]:place-items-center [&_button]:rounded-full [&_button]:border-0 [&_button]:bg-[#111] [&_button]:text-white [&_button_svg]:size-3 [&_button_svg]:fill-current" key={workflow.title}>
                    <span><Workflow /></span>
                    <div>
                      <strong>{workflow.title}</strong>
                      <small>{workflow.prompt}</small>
                      <em>{workflow.tools}</em>
                    </div>
                    <button type="button" tabIndex={-1}>
                      <Play />
                    </button>
                    {index === 0 && <i className="absolute inset-y-0 left-0 w-[0.22rem] bg-[#ff7900]" />}
                  </div>
                ))}
              </div>
            </article>

            <article id="quick-actions" className="relative scroll-mt-24 overflow-hidden rounded-[clamp(1.8rem,3.4vw,3rem)] border border-[rgba(17,16,15,0.1)] shadow-[0_1.5rem_4rem_rgba(23,18,13,0.08)] [&_h3]:mt-[1.35rem] [&_h3]:mb-[1.25rem] [&_h3]:max-w-[700px] [&_h3]:text-left [&_h3]:text-[clamp(2.65rem,5vw,5.15rem)] [&_h3]:font-[450] [&_h3]:leading-[0.94] [&_h3]:tracking-[-0.055em] [&_p]:m-0 [&_p]:max-w-[610px] [&_p]:text-left [&_p]:text-[clamp(1rem,1.45vw,1.22rem)] [&_p]:font-[390] [&_p]:leading-[1.45] [&_p]:text-[rgba(17,16,15,0.63)] max-[700px]:rounded-[1.75rem] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)] max-[700px]:[&_p]:text-[0.98rem] min-h-[710px] bg-[#0b0b0c] p-[clamp(1.7rem,3.7vw,3.1rem)] text-white after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:border after:border-white/10 after:content-[''] [&>div:first-child_p]:!text-white/60 max-[1000px]:min-h-[700px] max-[700px]:min-h-0 max-[700px]:p-6">
              <div className="relative z-[2] flex flex-col items-start [&_h3]:mt-[1.2rem] [&_h3]:text-[clamp(2.4rem,4vw,3.9rem)] max-[700px]:[&_h3]:text-[clamp(2.5rem,12vw,3.8rem)]">
                <FeatureLabel number="08">Quick Actions</FeatureLabel>
                <h3>Turn any selection into an action.</h3>
                <p>
                  Save the prompt and capabilities once, then run it on selected
                  text or Finder files from the compact menu.
                </p>
              </div>
              <div className="absolute right-[clamp(1rem,3vw,2.25rem)] bottom-[clamp(1rem,3vw,2.25rem)] left-[clamp(1rem,3vw,2.25rem)] overflow-hidden rounded-[1.35rem] border border-white/10 bg-[#111113] p-[0.65rem] shadow-[0_1.5rem_3rem_rgba(0,0,0,0.3)] [&>p]:m-0 [&>p]:px-[0.55rem] [&>p]:pt-[0.8rem] [&>p]:pb-[0.35rem] [&>p]:text-[0.55rem] [&>p]:font-semibold [&>p]:uppercase [&>p]:tracking-[0.06em] [&>p]:text-white/40 max-[700px]:relative max-[700px]:right-auto max-[700px]:bottom-auto max-[700px]:left-auto max-[700px]:mt-8" aria-hidden="true">
                <div className="grid min-h-[2.8rem] grid-cols-[auto_minmax(0,1fr)] items-center gap-[0.55rem] rounded-[0.8rem] border border-white/[0.08] bg-[#0c0c0d] px-[0.7rem] [&_strong]:text-[1.1rem] [&_strong]:font-medium [&_strong]:text-[#ff7900] [&_span]:text-[0.62rem] [&_span]:text-white/35">
                  <strong>/</strong>
                  <span>Search actions and commands</span>
                </div>
                <p>Workflows</p>
                <div className="grid min-h-[3.65rem] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.65rem] rounded-[0.8rem] p-[0.55rem] [&>span]:grid [&>span]:size-8 [&>span]:place-items-center [&>span]:rounded-[0.65rem] [&>span]:bg-white/[0.06] [&>span]:text-white/70 [&>span_svg]:size-[0.85rem] [&>span_svg]:stroke-[1.7] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.67rem] [&_strong]:font-medium [&_small]:mt-[0.15rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.55rem] [&_small]:text-white/45 [&_kbd]:font-[inherit] [&_kbd]:text-[0.62rem] [&_kbd]:text-white/35 bg-white/[0.08]">
                  <span><Workflow /></span>
                  <div>
                    <strong>Prepare discovery call</strong>
                    <small>Run saved workflow</small>
                  </div>
                  <kbd>↵</kbd>
                </div>
                <p>Quick Actions</p>
                <div className="grid min-h-[3.65rem] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.65rem] rounded-[0.8rem] p-[0.55rem] [&>span]:grid [&>span]:size-8 [&>span]:place-items-center [&>span]:rounded-[0.65rem] [&>span]:bg-white/[0.06] [&>span]:text-white/70 [&>span_svg]:size-[0.85rem] [&>span_svg]:stroke-[1.7] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.67rem] [&_strong]:font-medium [&_small]:mt-[0.15rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.55rem] [&_small]:text-white/45 [&_kbd]:font-[inherit] [&_kbd]:text-[0.62rem] [&_kbd]:text-white/35">
                  <span><Zap /></span>
                  <div>
                    <strong>Rewrite in my voice</strong>
                    <small>Use selected text as context</small>
                  </div>
                </div>
                <div className="grid min-h-[3.65rem] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-[0.65rem] rounded-[0.8rem] p-[0.55rem] [&>span]:grid [&>span]:size-8 [&>span]:place-items-center [&>span]:rounded-[0.65rem] [&>span]:bg-white/[0.06] [&>span]:text-white/70 [&>span_svg]:size-[0.85rem] [&>span_svg]:stroke-[1.7] [&>div]:flex [&>div]:min-w-0 [&>div]:flex-col [&_strong]:text-[0.67rem] [&_strong]:font-medium [&_small]:mt-[0.15rem] [&_small]:overflow-hidden [&_small]:text-ellipsis [&_small]:whitespace-nowrap [&_small]:text-[0.55rem] [&_small]:text-white/45 [&_kbd]:font-[inherit] [&_kbd]:text-[0.62rem] [&_kbd]:text-white/35">
                  <span><Code2 /></span>
                  <div>
                    <strong>Review selected files</strong>
                    <small>Use Finder selection as context</small>
                  </div>
                </div>
              </div>
            </article>
          </div>
        </div>
      </section>

      <section id="faq" className="bg-white px-[clamp(1rem,3vw,2rem)] py-[clamp(6rem,10vw,9rem)] text-[#11100f] max-[700px]:pt-[5.5rem]" aria-labelledby="faq-heading">
        <div className="mx-auto grid w-full max-w-[1180px] grid-cols-[minmax(0,0.78fr)_minmax(0,1.22fr)] gap-[clamp(3rem,8vw,8rem)] max-[1000px]:grid-cols-1 max-[1000px]:gap-16">
          <div className="self-start">
            <p className="m-0 inline-flex items-center gap-[0.55rem] text-xs font-semibold uppercase leading-none tracking-[0.12em] [&_svg]:size-4 [&_svg]:stroke-[1.8]">Good to know</p>
            <h2 id="faq-heading" className="sick mt-[1.6rem] text-left text-[clamp(3.9rem,7.2vw,6.8rem)] font-normal leading-[0.86] tracking-[-0.035em] max-[700px]:text-[clamp(3.7rem,17vw,5.4rem)]">
              Small surface.
              <br />
              Straight answers.
            </h2>
          </div>
          <div className="border-t border-black/20 [&_details]:border-b [&_details]:border-black/20">
            <details name="detach-faq" className="group" open>
              <summary className="relative flex min-h-[5.3rem] cursor-pointer list-none items-center pr-[2.6rem] text-left text-[clamp(1rem,1.4vw,1.2rem)] font-medium marker:hidden after:absolute after:right-[0.4rem] after:text-[1.3rem] after:font-normal after:text-[#ff7900] after:content-['+'] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#ff7900] group-open:after:content-['−'] [&::-webkit-details-marker]:hidden">Do I need another AI subscription?</summary>
              <p className="mt-[-0.5rem] mb-0 max-w-[620px] py-0 pr-[2.5rem] pb-[1.7rem] text-left text-[0.95rem] leading-[1.55] text-black/60">
                No Detach model plan is required. Detach runs the Codex, Claude
                Code, or Grok CLI already installed and signed in on your Mac.
              </p>
            </details>
            <details name="detach-faq" className="group">
              <summary className="relative flex min-h-[5.3rem] cursor-pointer list-none items-center pr-[2.6rem] text-left text-[clamp(1rem,1.4vw,1.2rem)] font-medium marker:hidden after:absolute after:right-[0.4rem] after:text-[1.3rem] after:font-normal after:text-[#ff7900] after:content-['+'] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#ff7900] group-open:after:content-['−'] [&::-webkit-details-marker]:hidden">What can Detach automate?</summary>
              <p className="mt-[-0.5rem] mb-0 max-w-[620px] py-0 pr-[2.5rem] pb-[1.7rem] text-left text-[0.95rem] leading-[1.55] text-black/60">
                It can work inside your signed-in Chrome profile and control
                accessible macOS apps: opening windows, clicking controls, typing,
                scrolling, using shortcuts, and gathering context.
              </p>
            </details>
            <details name="detach-faq" className="group">
              <summary className="relative flex min-h-[5.3rem] cursor-pointer list-none items-center pr-[2.6rem] text-left text-[clamp(1rem,1.4vw,1.2rem)] font-medium marker:hidden after:absolute after:right-[0.4rem] after:text-[1.3rem] after:font-normal after:text-[#ff7900] after:content-['+'] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#ff7900] group-open:after:content-['−'] [&::-webkit-details-marker]:hidden">Can an agent read my saved password?</summary>
              <p className="mt-[-0.5rem] mb-0 max-w-[620px] py-0 pr-[2.5rem] pb-[1.7rem] text-left text-[0.95rem] leading-[1.55] text-black/60">
                No. Password values stay in macOS Keychain. The agent requests a
                verified browser fill, and you approve each use with Touch ID.
              </p>
            </details>
            <details name="detach-faq" className="group">
              <summary className="relative flex min-h-[5.3rem] cursor-pointer list-none items-center pr-[2.6rem] text-left text-[clamp(1rem,1.4vw,1.2rem)] font-medium marker:hidden after:absolute after:right-[0.4rem] after:text-[1.3rem] after:font-normal after:text-[#ff7900] after:content-['+'] focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-[#ff7900] group-open:after:content-['−'] [&::-webkit-details-marker]:hidden">Workflow or Quick Action?</summary>
              <p className="mt-[-0.5rem] mb-0 max-w-[620px] py-0 pr-[2.5rem] pb-[1.7rem] text-left text-[0.95rem] leading-[1.55] text-black/60">
                A Workflow launches a saved repeat task in one click. A Quick
                Action runs a saved instruction against the text or files you have
                selected right now.
              </p>
            </details>
          </div>
        </div>
      </section>

      <section id="download" className="bg-white px-[clamp(1rem,3vw,2rem)] pb-[clamp(1rem,3vw,2rem)]">
        <div className="mx-auto flex min-h-[min(86vh,820px)] w-full max-w-[1500px] flex-col items-center justify-center overflow-hidden rounded-[clamp(1.8rem,3.5vw,3.5rem)] bg-[radial-gradient(circle_at_50%_120%,rgba(255,121,0,0.5),transparent_42%)] bg-[#050505] px-5 py-[clamp(3rem,7vw,6rem)] text-center text-white [&>img]:size-[clamp(3.2rem,6vw,5rem)] [&>p]:mt-[1.8rem] [&>p]:mb-0 [&>p]:text-[0.74rem] [&>p]:font-[500] [&>p]:uppercase [&>p]:tracking-[0.12em] [&>p]:text-white/50 [&>h2]:mt-[1.2rem] [&>h2]:mb-0 [&>h2]:max-w-[1050px] [&>h2]:text-[clamp(4.2rem,9.5vw,9rem)] [&>h2]:font-normal [&>h2]:leading-[0.84] [&>h2]:tracking-[-0.04em] [&>small]:mt-[0.85rem] [&>small]:text-[0.65rem] [&>small]:text-white/35 max-[700px]:min-h-[650px] max-[700px]:[&>h2]:text-[clamp(4rem,18vw,6rem)]">
          <Image src="/icon.svg" alt="" width={72} height={72} />
          <p>Built for macOS</p>
          <h2 className="sick">One keystroke. The whole Mac.</h2>
          <a
            href="https://qymrzmmsroxkteaxbgoo.supabase.co/storage/v1/object/public/updates/Lazzy.dmg"
            className="mt-[clamp(2.5rem,5vw,4rem)] inline-flex min-h-[3.25rem] items-center gap-[0.55rem] rounded-full bg-white px-[1.15rem] text-[0.82rem] font-semibold text-[#0a0a0a] no-underline transition duration-200 hover:-translate-y-0.5 hover:bg-[#ffd8b5] focus-visible:-translate-y-0.5 focus-visible:bg-[#ffd8b5] focus-visible:outline-none motion-reduce:transition-none [&_svg]:size-[0.9rem]"
          >
            <span></span>
            Download for macOS
            <ArrowUpRight aria-hidden="true" />
          </a>
          <small>Requires macOS 14 or later.</small>
        </div>
      </section>

      <footer className="mx-auto grid min-h-32 w-full max-w-[1180px] grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-8 bg-white px-[clamp(1rem,3vw,2rem)] py-5 text-[#11100f] [&>p]:m-0 [&>p]:text-center [&>p]:text-[0.74rem] [&>p]:text-black/50 [&>div]:flex [&>div]:items-center [&>div]:gap-5 [&>div_a]:text-[0.72rem] [&>div_a]:text-black/65 [&>div_a]:no-underline [&_a:hover]:text-[#ff7900] [&_a:focus-visible]:text-[#ff7900] [&_a:focus-visible]:outline-none max-[700px]:flex max-[700px]:min-h-44 max-[700px]:flex-col max-[700px]:justify-center max-[700px]:gap-[1.2rem] max-[700px]:[&>p]:order-3">
        <a href="#" className="inline-flex items-center gap-1 text-inherit no-underline [&_img]:rounded-[0.55rem] [&_img]:bg-[#111] [&_img]:p-[0.3rem] [&_strong]:text-base [&_strong]:font-semibold" aria-label="Detach, back to top">
          <Image src="/icon.svg" alt="" width={30} height={30} />
          <strong>Detach</strong>
        </a>
        <p>Ergonomic AI agents for your entire macOS.</p>
        <div>
          <a href="#features">Features</a>
          <a href="#security">Security</a>
          <a href="#faq">FAQ</a>
        </div>
      </footer>
    </>
  );
}
