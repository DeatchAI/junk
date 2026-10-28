import { Arrow, DownloadButton } from "@/components/landing/shared";
import { ClosingCta, Pricing } from "@/components/landing/pricing";
import { ProductDemo } from "@/components/landing/demo/product-demo";
import { Header, Footer } from "@/components/landing/navigation";
import { AgentStrip } from "@/components/landing/agent-strip";
import { Workflow } from "@/components/landing/workflow";
import { AutoRouter } from "@/components/landing/auto-router";

export default function Home() {
  return <>
    <a className="fixed -top-20 left-5 z-50 bg-foreground p-3 text-background focus:top-4" href="#main">Skip to content</a>
    <Header />
    <main id="main">
      <section className="page-width pt-16 md:pt-[clamp(5rem,8vw,7rem)]" aria-labelledby="hero-title">
        <h1 className="max-w-xl text-4xl gothic leading-tight tracking-tight" id="hero-title">
          All your coding agents.<br />One detached interface.
        </h1>
        <div className="mt-6 flex flex-wrap items-center gap-2.5">
          <DownloadButton />
          <a className="inline-flex min-h-10 items-center justify-center gap-2 rounded-full bg-surface px-5 py-2.5 text-[13px] transition-colors hover:bg-foreground/10" href="#film">Try the demo <Arrow /></a>
        </div>
      </section>
      <ProductDemo />
      <AgentStrip />
      <Workflow />
      <AutoRouter />
      <Pricing />
      <ClosingCta />
    </main>
    <Footer />
  </>;
}
