import { type ElementType, type HTMLAttributes } from "react";

const JITTER_CSS = `
  @keyframes stopmotion {
    0%,   24.9% { filter: url(#jitter-0); }
    25%,  49.9% { filter: url(#jitter-1); }
    50%,  74.9% { filter: url(#jitter-2); }
    75%,  99.9% { filter: url(#jitter-3); }
  }
  .jitter-text {
    animation: stopmotion 0.4s steps(1) infinite;
  }
`;

/**
 * JitterTitle
 *
 * Wraps any heading (or block element) in the stop-motion SVG jitter effect.
 *
 * Usage:
 *   <JitterTitle as="h1" className="text-[clamp(4rem,19vw,6rem)] font-medium apple">
 *     Cursor for macOS
 *   </JitterTitle>
 *
 * Props:
 *   as        – the HTML tag to render (default: "h2")
 *   className – forwarded to the heading element
 *   children  – heading content (can include JSX)
 */
interface JitterTitleProps extends HTMLAttributes<HTMLElement> {
  /** HTML element to render. Defaults to "h2". */
  as?: ElementType;
}

export function JitterTitle({
  as: Tag = "h2",
  className = "",
  children,
  ...rest
}: JitterTitleProps) {
  return (
    <>
      {/* Hidden SVG that defines the four jitter filter frames */}
      <svg
        className="absolute"
        width={0}
        height={0}
        aria-hidden="true"
        focusable="false"
      >
        <defs>
          <filter id="jitter-0" x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence
              type="turbulence"
              baseFrequency="0.04"
              numOctaves={3}
              seed={3}
              result="noise"
            />
            <feDisplacementMap
              in="SourceGraphic"
              in2="noise"
              scale={3}
              xChannelSelector="R"
              yChannelSelector="G"
            />
          </filter>
          <filter id="jitter-1" x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence
              type="turbulence"
              baseFrequency="0.04"
              numOctaves={3}
              seed={10}
              result="noise"
            />
            <feDisplacementMap
              in="SourceGraphic"
              in2="noise"
              scale={3}
              xChannelSelector="R"
              yChannelSelector="G"
            />
          </filter>
          <filter id="jitter-2" x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence
              type="turbulence"
              baseFrequency="0.04"
              numOctaves={3}
              seed={17}
              result="noise"
            />
            <feDisplacementMap
              in="SourceGraphic"
              in2="noise"
              scale={3}
              xChannelSelector="R"
              yChannelSelector="G"
            />
          </filter>
          <filter id="jitter-3" x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence
              type="turbulence"
              baseFrequency="0.04"
              numOctaves={3}
              seed={24}
              result="noise"
            />
            <feDisplacementMap
              in="SourceGraphic"
              in2="noise"
              scale={3}
              xChannelSelector="R"
              yChannelSelector="G"
            />
          </filter>
        </defs>
      </svg>

      {/* Keyframe definition injected inline */}
      {/* eslint-disable-next-line react/no-danger */}
      <style dangerouslySetInnerHTML={{ __html: JITTER_CSS }} />

      <Tag className={`jitter-text ${className}`} {...rest}>
        {children}
      </Tag>
    </>
  );
}
