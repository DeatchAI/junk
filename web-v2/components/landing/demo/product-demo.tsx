"use client";

import { useEffect, useLayoutEffect, useRef } from "react";
import { ActivityIsland } from "./demo-composer";
import { DemoWindow } from "./demo-window";
import { FilePreview, HistoryPanel } from "./demo-menus";
import { IconButton } from "./demo-icons";
import { useDemoWorkspace } from "./demo-workspace";
import {
  composerLayerClasses,
  demoCanvasClasses,
  demoCaptionClasses,
  productCanvasClasses,
  productSectionClasses,
  reopenClasses,
  stageToolsClasses,
} from "./demo-classes";
import Image from "next/image"

export function ProductDemo() {
  const workspace = useDemoWorkspace();
  const stage = useRef<HTMLDivElement>(null);
  const historyTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useLayoutEffect(() => {
    if (workspace.state.historyOpen) stage.current?.querySelector<HTMLInputElement>('[data-history-panel] input')?.focus({ preventScroll: true });
  }, [workspace.state.historyOpen]);

  useEffect(() => {
    function closeMenus(event: globalThis.PointerEvent) {
      if (!(event.target instanceof Element)) return;
      const target = event.target;
      const inStage = stage.current?.contains(target) ?? false;
      const inside = (selector: string) => inStage && !!target.closest(selector);
      if (!inside("[data-demo-menu], [data-menu-trigger]")) workspace.closeMenus();
      const changes = {
        ...(workspace.state.historyOpen && !inside("[data-history-panel], [data-history-trigger]") ? { historyOpen: false } : {}),
        ...(workspace.state.islandOpen && !inside("[data-activity-island]") ? { islandOpen: false } : {}),
      };
      if (Object.keys(changes).length) workspace.patch(changes);
      if (target === stage.current) stage.current.focus({ preventScroll: true });
    }
    function shortcuts(event: globalThis.KeyboardEvent) {
      const canvas = stage.current; if (!canvas) return;
      const rect = canvas.getBoundingClientRect();
      const focused = document.activeElement;
      const externalInput = focused instanceof HTMLElement && !canvas.contains(focused)
        && (focused.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(focused.tagName));
      if (rect.bottom <= 0 || rect.top >= window.innerHeight || externalInput || event.isComposing) return;
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.code === "Space") {
        event.preventDefault(); if (!event.repeat) workspace.addComposer(); return;
      }
      if (event.altKey && !event.ctrlKey && !event.metaKey && event.code === "KeyH") {
        event.preventDefault(); if (!event.repeat) workspace.patch({ historyOpen: !workspace.state.historyOpen }); return;
      }
      if (event.key !== "Escape" || event.repeat) return;
      event.preventDefault();
      if (workspace.state.previewFile) workspace.patch({ previewFile: null });
      else if (workspace.state.historyOpen) workspace.patch({ historyOpen: false });
      else workspace.dismissFrontComposer();
      canvas.focus({ preventScroll: true });
    }
    document.addEventListener("pointerdown", closeMenus);
    document.addEventListener("keydown", shortcuts);
    return () => { document.removeEventListener("pointerdown", closeMenus); document.removeEventListener("keydown", shortcuts); };
  }, [workspace]);

  return <section className={productSectionClasses} id="film" aria-label="Interactive Detach app demo">
    <div className={`${demoCanvasClasses} ${productCanvasClasses}`} data-appearance={workspace.state.appearance} data-demo-canvas="" ref={stage} tabIndex={-1} aria-label="Detach desktop canvas">
    {/* <Image src="/assets/image.png" alt="" width={1400} height={24} /> */}
      <div className={composerLayerClasses}>
        {workspace.state.windows.map(spec => <DemoWindow key={`${workspace.state.generation}-${spec.id}`} spec={spec} workspace={workspace} canvas={stage}/>)}
      </div>
      <ActivityIsland workspace={workspace}/>
      <HistoryPanel workspace={workspace}/>
      {!workspace.state.historyOpen && <button type="button" className="absolute top-[20%] bottom-[20%] left-0 z-[3] w-[10px] border-0 bg-transparent p-0" aria-label="Show conversation history" data-history-trigger=""
        onMouseEnter={() => { historyTimer.current = setTimeout(() => workspace.patch({ historyOpen: true }), 140); }}
        onMouseLeave={() => { if (historyTimer.current) clearTimeout(historyTimer.current); }}
        onClick={() => workspace.patch({ historyOpen: true })} onFocus={() => workspace.patch({ historyOpen: true })}/>}
      {!workspace.state.windows.some(window => window.visible) && <button type="button" className={reopenClasses} onClick={() => workspace.addComposer()}>New composer<span>⌥ Space</span></button>}
      <div className={stageToolsClasses}>
        <IconButton icon="newChat" label="New composer" onClick={() => workspace.addComposer()}/>
        <IconButton icon={workspace.state.appearance === "dark" ? "sun" : "moon"} label={`Use ${workspace.state.appearance === "dark" ? "light" : "dark"} appearance`}
          onClick={() => workspace.patch({ appearance: workspace.state.appearance === "dark" ? "light" : "dark" })}/>
        <IconButton icon="reset" label="Reset demo" onClick={workspace.reset}/>
      </div>
      {workspace.state.previewFile && <FilePreview file={workspace.state.previewFile} onClose={() => workspace.patch({ previewFile: null })}/>}
    </div>
    <div className={demoCaptionClasses}><p><kbd>⌥ Space</kbd> New composer <span>·</span> <kbd>⌥ H</kbd> History <span>·</span> <kbd>Esc</kbd> Hide composer</p><span>Drag anywhere around the controls. Try @ or /.</span></div>
  </section>;
}
