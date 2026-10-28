"use client";

import { useSyncExternalStore } from "react";

const subscribe = (callback: () => void) => {
  window.addEventListener("detach-theme", callback);
  return () => window.removeEventListener("detach-theme", callback);
};

export function ThemeToggle() {
  const theme = useSyncExternalStore(subscribe, () => document.documentElement.dataset.theme ?? "system", () => "system");
  function toggle() {
    const dark = theme === "dark" || (theme === "system" && window.matchMedia("(prefers-color-scheme: dark)").matches);
    const next = dark ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("detach-theme", next); } catch { /* Theme still works without storage. */ }
    window.dispatchEvent(new Event("detach-theme"));
  }
  return <button className="grid size-8 cursor-pointer place-items-center rounded-full bg-transparent text-foreground hover:bg-background [&_svg]:size-5" onClick={toggle} aria-label="Toggle light and dark mode" title="Toggle light and dark mode"><svg className="hidden dark:block" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/></svg><svg className="block dark:hidden" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M20 15.5A8.5 8.5 0 0 1 8.5 4 8.5 8.5 0 1 0 20 15.5Z"/></svg></button>;
}
