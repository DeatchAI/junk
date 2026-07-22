"use client";

import { useState, useEffect } from "react";

const prompts = [
  "build me a dashboard to visualize & share the analytics metrics",
  "Review approval requests in our procurement tool. For each request over $5k, check whether the vendor exists in the SaaS inventory find the likely owner",
  "open X and reply to all comments my posts got in my style",
];


export default function TypewriterPrompt() {
  const [currentIndex, setCurrentIndex] = useState(0);
  const [displayedText, setDisplayedText] = useState("");
  const [isDeleting, setIsDeleting] = useState(false);
  const [isPaused, setIsPaused] = useState(false);

  useEffect(() => {
    const currentPrompt = prompts[currentIndex];
    
    if (isPaused) {
      const pauseTimer = setTimeout(() => {
        setIsPaused(false);
        setIsDeleting(true);
      }, 3000); // Pause for 3 seconds at the end
      return () => clearTimeout(pauseTimer);
    }

    if (!isDeleting && displayedText === currentPrompt) {
      setIsPaused(true);
      return;
    }

    if (isDeleting && displayedText === "") {
      setIsDeleting(false);
      setCurrentIndex((prev) => (prev + 1) % prompts.length);
      return;
    }

    const timeout = setTimeout(
      () => {
        setDisplayedText((prev) => {
          if (isDeleting) {
            return currentPrompt.substring(0, prev.length - 1);
          } else {
            return currentPrompt.substring(0, prev.length + 1);
          }
        });
      },
      isDeleting ? 15 : 35 // Faster deletion, slower typing
    );

    return () => clearTimeout(timeout);
  }, [displayedText, isDeleting, currentIndex, isPaused]);

  return (
    <div className="relative h-full flex flex-col">
      <div className="w-[calc(100%-1.65rem)] text-[#000000] font-[380] leading-[1.42] text-left text-[0.74rem] sm:text-[clamp(0.62rem,1vw,0.82rem)] flex-1 min-h-[4rem]">
        {displayedText}
        <span className="inline-block w-[2px] h-[0.9em] bg-black ml-[2px] animate-pulse" />
      </div>
    </div>
  );
}
