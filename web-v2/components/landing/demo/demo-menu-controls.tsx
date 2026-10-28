import { useEffect, useLayoutEffect, useRef, type HTMLAttributes, type ReactNode } from "react";
import { Icon, type IconName } from "./demo-icons";
import s from "./demo-panels.module.css";

export function MenuSurface({ placement = "above", children, ...props }: HTMLAttributes<HTMLDivElement> & { placement?: "above" | "below" | "right"; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const panel = ref.current;
    const canvas = panel?.closest<HTMLElement>("[data-demo-canvas]");
    if (!panel || !canvas) return;
    const fit = () => {
      const bounds = canvas.getBoundingClientRect();
      const rect = panel.getBoundingClientRect();
      const anchor = panel.parentElement!.getBoundingClientRect();
      const oldX = parseFloat(panel.style.getPropertyValue("--popover-x")) || 0;
      const oldY = parseFloat(panel.style.getPropertyValue("--popover-y")) || 0;
      const left = rect.left - oldX; const top = rect.top - oldY;
      let x = 0; let y = 0;
      if (placement === "below" && top + rect.height > bounds.bottom - 8) y = anchor.top - rect.height - 6 - top;
      if (placement === "above" && top < bounds.top + 8) y = anchor.bottom + 6 - top;
      if (placement === "right" && left + rect.width > bounds.right - 8) x = anchor.left - rect.width - 6 - left;
      x = Math.max(bounds.left + 8 - left, Math.min(x, bounds.right - 8 - left - rect.width));
      y = Math.max(bounds.top + 8 - top, Math.min(y, bounds.bottom - 8 - top - rect.height));
      panel.style.setProperty("--popover-x", `${x}px`); panel.style.setProperty("--popover-y", `${y}px`);
    };
    fit();
    const frame = requestAnimationFrame(fit);
    const resize = new ResizeObserver(fit); resize.observe(panel); resize.observe(canvas);
    const movement = new MutationObserver(fit); movement.observe(panel.parentElement!, { attributes: true, attributeFilter: ["style"] });
    return () => { cancelAnimationFrame(frame); resize.disconnect(); movement.disconnect(); };
  }, [placement, children]);
  return <div ref={ref} data-demo-popover="" {...props}>{children}</div>;
}

export function MenuRow({ label, value, icon, checked, nested, active, onClick, onMouseEnter, onMouseLeave }: {
  label: string; value?: string; icon?: IconName; checked?: boolean; nested?: boolean; active?: boolean;
  onClick: () => void; onMouseEnter?: () => void; onMouseLeave?: () => void;
}) {
  return <button type="button" className={s.menuRow} data-active={active} onClick={onClick} onMouseEnter={onMouseEnter} onMouseLeave={onMouseLeave}>
    {icon && <Icon name={icon}/>}<span>{label}</span><span className={s.rowValue}>{value}</span>
    {nested ? <Icon name="right" size={12}/> : checked ? <Icon name="check" size={12}/> : null}
  </button>;
}

export function NestedMenuRow({ label, value = "", icon, active, onOpen, children }: { label: string; value?: string; icon?: IconName; active?: boolean; onOpen: () => void; children: ReactNode }) {
  const hoverTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (hoverTimer.current) clearTimeout(hoverTimer.current); }, []);
  const clearHover = () => { if (hoverTimer.current) clearTimeout(hoverTimer.current); };
  return <div className={s.nestedRow}>
    <MenuRow label={label} value={value} icon={icon} active={active} nested onClick={() => { clearHover(); onOpen(); }}
      onMouseEnter={() => { clearHover(); hoverTimer.current = setTimeout(onOpen, 150); }} onMouseLeave={clearHover}/>
    {children}
  </div>;
}
