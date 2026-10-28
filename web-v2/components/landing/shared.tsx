import Image from "next/image";

export const downloadUrl = "https://github.com/DeatchAI/App/releases/latest/download/Detach.dmg";

export function Arrow({ diagonal = false }: { diagonal?: boolean }) {
  return <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6" aria-hidden="true"><path d={diagonal ? "M6 18 18 6M6 6h12v12" : "M4 12h15m-6-6 6 6-6 6"} /></svg>;
}

export function Brand({ iconOnly = false }: { iconOnly?: boolean }) {
  return <a className="inline-flex w-fit items-center text-[18px] font-medium tracking-[-0.065em]" href="#" aria-label="Detach home">
    <span className="flex size-9 overflow-hidden rounded-md [&_img]:size-full [&_img]:object-cover">
      <Image src="/logo-light.svg" width={38} height={38} alt="" className="dark:hidden" />
      <Image src="/logo.svg" width={38} height={38} alt="" className="hidden dark:block" />
    </span>{!iconOnly && <span className="brand">Detach</span>}
  </a>;
}

export function DownloadButton({ children, className = "", compact = false }: { children?: React.ReactNode; className?: string; compact?: boolean }) {
  return <a className={`inline-flex shrink-0 items-center justify-center gap-2 rounded-full bg-foreground text-background transition-opacity hover:opacity-80 ${compact ? "min-h-8 px-3.5 py-1.5 text-xs" : "min-h-10 px-5 py-2.5 text-[13px]"} ${className}`} href={downloadUrl}>
    {children ?? <>Download for macOS <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M12 3v13m-5-5 5 5 5-5M5 18v3h14v-3" /></svg></>}
  </a>;
}
