"use client";

import { useEffect, useRef } from "react";

type DockApp = {
  name: string;
  icon: string;
};

const apps: DockApp[] = [
  {
    name: "Notion",
    icon: "https://framerusercontent.com/images/2HvSuX7uCYBwdeEUPchOMgqR1ac.png",
  },
  {
    name: "Chrome",
    icon: "https://framerusercontent.com/images/2luq8cr5TjUFISJRQfItlcl6pE.png",
  },
  {
    name: "WhatsApp",
    icon: "https://framerusercontent.com/images/Aiwg1aoOFgKcgBRy4r36GrHn64s.png",
  },
  {
    name: "Slack",
    icon: "https://framerusercontent.com/images/PHLKjekq3wcpNJNQRyGa7qog.png",
  },
  {
    name: "X",
    icon: "https://framerusercontent.com/images/Qz6g60asFFM1y9n1CS8CtDVVZk0.png",
  },
  {
    name: "LinkedIn",
    icon: "https://img.icons8.com/color/256/linkedin.png",
  },
  {
    name: "Google Docs",
    icon: "https://img.icons8.com/color/256/google-docs.png",
  },
  {
    name: "Figma",
    icon: "https://img.icons8.com/color/256/figma--v1.png",
  },
  {
    name: "Discord",
    icon: "https://img.icons8.com/color/256/discord-logo.png",
  },
  {
    name: "Spotify",
    icon: "https://img.icons8.com/color/256/spotify--v1.png",
  },
  {
    name: "Telegram",
    icon: "https://img.icons8.com/color/256/telegram-app.png",
  },
  {
    name: "Gmail",
    icon: "https://img.icons8.com/color/256/gmail-new.png",
  },
  {
    name: "Zoom",
    icon: "https://img.icons8.com/color/256/zoom.png",
  },
];

export default function AutoSlidingDock() {
  const viewportRef = useRef<HTMLDivElement | null>(null);
  const trackRef = useRef<HTMLDivElement | null>(null);
  const iconRefs = useRef<(HTMLDivElement | null)[]>([]);
  const frameRef = useRef<number | null>(null);

  useEffect(() => {
    const reducedMotion = window.matchMedia(
      "(prefers-reduced-motion: reduce)",
    ).matches;

    const animate = (time: number) => {
      const viewport = viewportRef.current;
      const track = trackRef.current;

      if (!viewport || !track) {
        frameRef.current = requestAnimationFrame(animate);
        return;
      }

      const viewportWidth = viewport.clientWidth;
      const trackWidth = track.scrollWidth;

      const maxTranslate = Math.max(
        0,
        trackWidth - viewportWidth,
      );

      /*
       * Smooth ping-pong movement:
       * 0 → 1 → 0
       *
       * Increase 0.00045 to make it faster.
       */
      const progress = reducedMotion
        ? 0.5
        : 0.5 - 0.5 * Math.cos(time * 0.00045);

      const translateX = -maxTranslate * progress;

      track.style.transform = `translate3d(${translateX}px, 0, 0)`;

      /*
       * The magnification point remains fixed in the middle
       * while the dock moves beneath it.
       */
      const focusX = viewportWidth / 2;
      const influenceRadius = 180;

      iconRefs.current.forEach((icon) => {
        if (!icon) return;

        const iconCenter =
          icon.offsetLeft +
          icon.offsetWidth / 2 +
          translateX;

        const signedDistance = iconCenter - focusX;
        const distance = Math.abs(signedDistance);

        const proximity = Math.max(
          0,
          1 - distance / influenceRadius,
        );

        // Smoothstep easing
        const eased =
          proximity * proximity * (3 - 2 * proximity);

        const scale = 1 + eased * 0.72;
        const lift = eased * 38;

        /*
         * Slightly pushes neighbouring icons away
         * from the currently enlarged icon.
         */
        const push =
          Math.sign(signedDistance) * eased * 13;

        icon.style.transform = `
          translate3d(${push}px, ${-lift}px, 0)
          scale(${scale})
        `;

        icon.style.zIndex = String(
          Math.round(eased * 100) + 1,
        );
      });

      frameRef.current = requestAnimationFrame(animate);
    };

    frameRef.current = requestAnimationFrame(animate);

    return () => {
      if (frameRef.current !== null) {
        cancelAnimationFrame(frameRef.current);
      }
    };
  }, []);

  return (
    <section
      className="
        relative isolate
        aspect-square w-full max-w-[980px]
        overflow-hidden
      "
    >
      

     


     
      {/* Clipped dock viewport */}
      <div
        ref={viewportRef}
        className="
          absolute left-0 right-0 top-[56%]
          h-[260px]
          overflow-hidden
          max-sm:top-[54%]
          max-sm:h-[210px]
        "
      >
        {/* Sliding dock track */}
        <div
          ref={trackRef}
          className="
            absolute bottom-[20px] left-0
            flex h-[205px] w-max
            items-end
            px-[40px]
            will-change-transform
            max-sm:h-[170px]
            max-sm:px-[26px]
          "
        >
          {/* Glass dock background */}
          <div
            className="
              pointer-events-none
              absolute inset-x-0 bottom-0
              h-[156px]
             bg-black/15
              backdrop-blur-[18px]
              backdrop-saturate-[1.25]
              max-sm:h-[125px]
              max-sm:rounded-[24px]
            "
          />

          {/* Dock icons */}
          <div
            className="
              relative z-10
              flex h-full items-end
              gap-[34px]
              px-[30px] pb-[25px]
              max-sm:gap-[20px]
              max-sm:px-[20px]
              max-sm:pb-[18px]
            "
          >
            {apps.map((app, index) => (
              <div
                key={app.name}
                className="
                  flex h-[145px] w-[100px]
                  shrink-0 items-end justify-center
                  max-sm:h-[115px]
                  max-sm:w-[76px]
                "
              >
                <div
                  ref={(element) => {
                    iconRefs.current[index] = element;
                  }}
                  className="
                    relative z-[1]
                    h-[94px] w-[94px]
                    origin-bottom
                    will-change-transform
                    max-sm:h-[72px]
                    max-sm:w-[72px]
                  "
                >
                  <img
                    src={app.icon}
                    alt={app.name}
                    draggable={false}
                    className="
                      pointer-events-none
                      block h-full w-full
                      select-none
                      rounded-[22%]
                      object-cover
                      drop-shadow-[0_9px_8px_rgba(28,46,0,0.2)]
                    "
                  />
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* <div
          className="
            pointer-events-none
            absolute inset-y-0 left-0 z-30
            w-[70px]
            bg-gradient-to-r
            from-[#b8d164]/55 to-transparent
          "
        />

        <div
          className="
            pointer-events-none
            absolute inset-y-0 right-0 z-30
            w-[70px]
            bg-gradient-to-l
            from-[#cafa4e]/55 to-transparent
          "
        /> */}
      </div>
    </section>
  );
}