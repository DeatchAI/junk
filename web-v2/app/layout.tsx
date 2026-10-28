import type { Metadata } from "next";
import "./assets/globals.css";
import "./assets/palette.css";
import localFont from "next/font/local";

const inter = localFont({ src: "../public/inter.ttf", variable: "--font-inter", weight: "100 900", display: "swap" });

const geistMono = localFont({ src: "../public/geist-mono.woff2", variable: "--font-geist-mono", weight: "100 900", display: "swap" });

export const metadata: Metadata = {
  title: "Detach — Your agents, working. You, in your flow.",
  description: "A home for your AI coding agents on Mac. Send off a task, follow progress, and keep doing your thing with Detach.",
};

const themeScript = `(function(){try{var t=localStorage.getItem('detach-theme');if(t==='light'||t==='dark')document.documentElement.dataset.theme=t}catch(e){}})()`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="en" className={`${inter.variable} ${geistMono.variable}`} suppressHydrationWarning><head><script dangerouslySetInnerHTML={{ __html: themeScript }}/></head><body className="bg-background font-sans tracking-[-0.025em] text-foreground antialiased">{children}</body></html>;
}
