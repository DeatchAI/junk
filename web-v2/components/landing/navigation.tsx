import { Arrow, Brand, DownloadButton } from "./shared";
import { ThemeToggle } from "./theme-toggle";

const links = [
  // { label: "Product", href: "#film" },
  { label: "How it works", href: "#how-it-works" },
  // { label: "Agents", href: "#agents" },
  { label: "Pricing", href: "#pricing" },
];

export function Header() {
  return <header className="sticky top-0 z-40 bg-background/95 backdrop-blur-md">
    <nav className="page-width grid min-h-16 grid-cols-[1fr_auto] items-center gap-5 md:grid-cols-[1fr_auto_1fr]" aria-label="Main navigation">
      <Brand />
      <div className="hidden items-center gap-7 text-[13px] md:flex">
        {links.map(link => <a className="transition-opacity hover:opacity-60" href={link.href} key={link.href}>{link.label}</a>)}
      </div>
      <div className="flex items-center justify-end gap-5">
        <a className="hidden text-[13px] transition-opacity hover:opacity-60 lg:block" href="https://github.com/DeatchAI/App">GitHub</a>
        <DownloadButton compact>Download</DownloadButton>
      </div>
    </nav>
  </header>;
}

export function Footer() {
  return <footer className="bg-surface">
    <div className="page-width py-14 md:py-16">
      <div className="flex flex-col justify-between gap-10 sm:flex-row">
        <div><Brand /><p className="mt-4 text-sm leading-6 text-muted">Your agents. Your accounts.<br />A little more room to work.</p></div>
        <div className="grid grid-cols-2 gap-x-14 gap-y-4 text-[13px] sm:gap-x-20">
          <p className="text-muted">Product</p><p className="text-muted">Elsewhere</p>
          <a href="#film">Interactive demo</a><a className="flex items-center gap-2" href="https://github.com/DeatchAI/App">GitHub <Arrow diagonal /></a>
          <a href="#how-it-works">How it works</a><a href="#get-detach">Download for Mac</a>
          <a href="#pricing">Pricing</a><a href="#agents">Supported agents</a>
        </div>
      </div>
      <div className="mt-16 flex items-center justify-between gap-5 text-xs text-muted">
        <span>© 2026 Detach</span>
        <div className="flex items-center gap-5"><span className="hidden sm:inline">Made for your Mac.</span><ThemeToggle /></div>
      </div>
    </div>
  </footer>;
}
