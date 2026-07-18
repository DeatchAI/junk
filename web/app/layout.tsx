import type { Metadata } from "next";
import "./assets/globals.css";
import Navbar from "@/components/nav";

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://getlazzy.app",
  ),
  title: "Detach — AI agents for your entire Mac",
  description:
    "Run Codex, Claude Code, or Grok across your browser and macOS with detached tasks, secure sign-in, integrations, workflows, and quick actions.",
  icons: "/icon.png",
  openGraph: {
    title: "Detach — AI agents for your entire Mac",
    description:
      "Your existing agents, now able to work across your browser and macOS.",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "Detach — AI agents for your entire Mac",
    description:
      "Your existing agents, now able to work across your browser and macOS.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`h-full antialiased`}
    >
      <body className="min-h-full flex flex-col bg-black text-white">
       <Navbar />
        {children}
      </body>
    </html>
  );
}
