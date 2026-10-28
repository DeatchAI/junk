import { Arrow, DownloadButton } from "./shared";

const plans = [
  { name: "Monthly", description: "A little room to find your flow.", cadence: "Billed monthly", features: ["All supported coding agents", "Floating composer & activity island", "Your own accounts and models"], featured: false },
  { name: "Lifetime", description: "Your agents. A permanent home.", cadence: "One payment. Yours to keep.", features: ["Everything in Monthly", "No recurring app subscription", "One home for your daily workflow"], featured: true },
];

export function Pricing() {
  return <section className="page-width pb-20 md:pb-28" id="pricing" aria-labelledby="pricing-title">
    <div className="mb-8 grid gap-5 md:mb-10 md:grid-cols-2 md:items-end">
      <h2 className="text-[28px] leading-tight tracking-[-0.045em] md:text-[32px]" id="pricing-title">A home for your agents.<br /><span className="text-muted">On your terms.</span></h2>
      <p className="max-w-sm text-sm leading-6 text-muted md:justify-self-end">Bring the agents and accounts you already use.<br />Choose the way you want to make yourself at home.</p>
    </div>
    <div className="grid gap-4 sm:grid-cols-2">{plans.map(plan => <article className="flex flex-col rounded-sm bg-surface p-7 md:p-9" key={plan.name}>
      <div className="flex items-center justify-between gap-3"><h3 className="text-xl tracking-[-0.035em]">{plan.name}</h3>{plan.featured && <span className="rounded-full bg-background px-3 py-1.5 text-[10px]">One payment</span>}</div>
      <p className="mt-3 text-sm text-muted">{plan.description}</p>
      <p className="mt-10 text-[28px] tracking-[-0.045em]">Coming soon</p>
      <p className="mt-2 text-xs text-muted">{plan.cadence}</p>
      <ul className="mt-8 mb-9 space-y-4">{plan.features.map(feature => <li className="flex items-center gap-3 text-[13px]" key={feature}><span className="text-muted" aria-hidden="true">✓</span>{feature}</li>)}</ul>
      <a className={`mt-auto inline-flex min-h-10 w-fit items-center justify-center gap-4 rounded-full px-5 py-2.5 text-[13px] ${plan.featured ? "bg-foreground text-background" : "bg-background text-foreground"}`} href="#get-detach">Explore Detach <Arrow /></a>
    </article>)}</div>
    <p className="mt-5 text-xs leading-6 text-muted">Plan details are a preview. Final pricing and availability will be announced.</p>
  </section>;
}

export function ClosingCta() {
  return <section id="get-detach" className="page-width py-20 md:py-28">
    <h2 className="mb-7 text-[clamp(2.5rem,5.4vw,4.5rem)] leading-[1.08] tracking-[-0.055em]">A little less attached.<br /><span className="text-muted">A lot more in flow.</span></h2>
    <DownloadButton />
    <p className="mt-5 text-xs text-muted">Your agents. Your accounts. Made for Mac.</p>
  </section>;
}
