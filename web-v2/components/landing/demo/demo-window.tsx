import { useLayoutEffect, useRef, useState, type CSSProperties, type PointerEvent, type RefObject } from "react";
import { Composer } from "./demo-composer";
import { useDemo } from "./use-demo";
import type { DemoWindowSpec, DemoWorkspace } from "./demo-workspace";
import { workspaceClasses } from "./demo-classes";

type Drag = { x: number; y: number; startX: number; startY: number; minX: number; maxX: number; minY: number; maxY: number; moved: boolean };

export function DemoWindow({ spec, workspace, canvas, featurePreview = false }: { spec: DemoWindowSpec; workspace: DemoWorkspace; canvas: RefObject<HTMLDivElement | null>; featurePreview?: boolean }) {
  const demo = useDemo(spec, workspace);
  const element = useRef<HTMLDivElement>(null);
  const [position, setPosition] = useState(spec.offset);
  const currentPosition = useRef(spec.offset);
  const drag = useRef<Drag | null>(null);
  const suppressClick = useRef(false);

  useLayoutEffect(() => workspace.register(spec.id, {
    dismissTransient: demo.dismissTransient, closeMenu: demo.closeMenu, selectBranch: demo.switchBranch,
  }), [demo, spec.id, workspace]);

  useLayoutEffect(() => {
    if (spec.visible && spec.focusVersion > 0) element.current?.querySelector<HTMLElement>('[contenteditable="true"]')?.focus({ preventScroll: true });
  }, [spec.focusVersion, spec.visible]);

  useLayoutEffect(() => {
    if (!spec.visible || !element.current) return;
    const panel = element.current;
    let observer: ResizeObserver | undefined;
    const frame = requestAnimationFrame(() => {
      const surface = canvas.current; if (!surface) return;
      const clamp = () => {
        const bounds = surface.getBoundingClientRect();
        const rect = panel.getBoundingClientRect();
        const dx = rect.left < bounds.left + 8 ? bounds.left + 8 - rect.left : rect.right > bounds.right - 8 ? bounds.right - 8 - rect.right : 0;
        const dy = rect.top < bounds.top + 8 ? bounds.top + 8 - rect.top : rect.bottom > bounds.bottom - 8 ? bounds.bottom - 8 - rect.bottom : 0;
        if (Math.abs(dx) < .5 && Math.abs(dy) < .5) return;
        const next = { x: currentPosition.current.x + dx, y: currentPosition.current.y + dy };
        currentPosition.current = next; setPosition(next);
      };
      observer = new ResizeObserver(clamp); observer.observe(panel); observer.observe(surface); clamp();
    });
    return () => { cancelAnimationFrame(frame); observer?.disconnect(); };
  }, [canvas, spec.visible]);

  function startDrag(event: PointerEvent<HTMLDivElement>) {
    workspace.focusWindow(spec.id);
    if (event.button !== 0 || !(event.target instanceof Element)
      || event.target.closest('button, input, textarea, a, [contenteditable="true"], [data-no-drag], [data-demo-menu], [role="dialog"]')
      || !element.current || !canvas.current) return;
    const bounds = canvas.current.getBoundingClientRect();
    const rect = element.current.getBoundingClientRect();
    const { x, y } = currentPosition.current;
    drag.current = { x, y, startX: event.clientX, startY: event.clientY,
      minX: x + bounds.left + 8 - rect.left, maxX: x + bounds.right - 8 - rect.right,
      minY: y + bounds.top + 8 - rect.top, maxY: y + bounds.bottom - 8 - rect.bottom, moved: false };
    event.currentTarget.setPointerCapture(event.pointerId);
    event.preventDefault();
  }
  function moveDrag(event: PointerEvent<HTMLDivElement>) {
    const origin = drag.current; if (!origin) return;
    if (Math.hypot(event.clientX - origin.startX, event.clientY - origin.startY) > 3) origin.moved = true;
    const next = { x: Math.min(origin.maxX, Math.max(origin.minX, origin.x + event.clientX - origin.startX)),
      y: Math.min(origin.maxY, Math.max(origin.minY, origin.y + event.clientY - origin.startY)) };
    currentPosition.current = next; setPosition(next);
  }
  function endDrag(event: PointerEvent<HTMLDivElement>) {
    suppressClick.current = drag.current?.moved ?? false; drag.current = null;
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
  }

  if (!spec.visible) return null;
  const placementClasses = featurePreview
    ? "left-1/2 bottom-[120px] w-[min(520px,calc(100%_-_32px))] max-[600px]:bottom-[58px] max-[600px]:w-[calc(100%_-_24px)]"
    : demo.state.expanded
      ? "left-[42%] bottom-[54px] w-[520px] max-[800px]:left-1/2 max-[800px]:bottom-[85px] max-[600px]:bottom-[52px] max-[600px]:w-[calc(100%_-_24px)]"
      : "left-[42%] bottom-[96px] w-[520px] max-[800px]:left-1/2 max-[800px]:bottom-[85px] max-[600px]:bottom-[76px] max-[600px]:w-[calc(100%_-_24px)]";
  return <div ref={element} className={`${workspaceClasses} ${placementClasses}`}
    data-window-id={spec.id} role="group" aria-label={spec.id.replace("composer-", "Composer ")}
    style={{ "--drag-x": `${position.x}px`, "--drag-y": `${position.y}px`, zIndex: spec.order } as CSSProperties}
    onPointerDown={startDrag} onPointerMove={moveDrag} onPointerUp={endDrag} onPointerCancel={endDrag}
    onFocusCapture={() => workspace.focusWindow(spec.id)}
    onClickCapture={event => { if (suppressClick.current) { event.preventDefault(); event.stopPropagation(); suppressClick.current = false; } }}>
    <Composer demo={demo}/>
  </div>;
}
