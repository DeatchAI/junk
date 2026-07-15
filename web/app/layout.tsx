import type { Metadata } from "next";
import "./assets/globals.css";
import Navbar from "@/components/nav";

export const metadata: Metadata = {
  title: "Detach - Use AI Ergonomically",
  description: "Detached coding, automation & work.",
  icons: "/icon.png"
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
      <body className="min-h-full flex flex-col">
       <Navbar />
        {children}
      </body>
    </html>
  );
}
