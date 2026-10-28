"use client";

import { useEffect, useRef } from "react";
import { ActivityIsland } from "./demo-composer";
import { IconButton } from "./demo-icons";
import { FilePreview, HistoryPanel } from "./demo-menus";
import { DemoWindow } from "./demo-window";
import { useDemoWorkspace, type SharedDemoState } from "./demo-workspace";
import { featureMessages, featureRuns } from "./feature-demo-data";
import { composerLayerClasses, demoCanvasClasses, featureCanvasClasses, reopenClasses, stageToolsClasses } from "./demo-classes";

export type FeaturePreviewKind = "composer" | "activity" | "history";

const initialStates: Record<FeaturePreviewKind, Partial<SharedDemoState>> = {
  composer: {
    appearance: "light",
    windows: [{ id: "composer-1", conversationId: "feature-composer", title: "Fix expanded composer sizing", project: "detach", agent: "codex",
      visible: true, order: 1, focusVersion: 0, messages: featureMessages,
      placeholder: "Ask your agent… @ context · / commands", offset: { x: 0, y: 0 } }],
  },
  activity: { appearance: "dark", windows: [], activeWindowId: "", islandOpen: true, runs: featureRuns },
  history: { appearance: "light", windows: [], activeWindowId: "", historyOpen: true },
};

const labels: Record<FeaturePreviewKind, string> = {
  composer: "Interactive composer preview",
  activity: "Interactive activity notch preview",
  history: "Interactive history notch preview",
};

const featureBackgrounds: Record<FeaturePreviewKind, string> = {
  composer: "before:bg-[url('/demo-bgs/1.png')]",
  activity: "before:bg-[url('/demo-bgs/3.png')]",
  history: "before:bg-[url('/demo-bgs/5.png')]",
};

export function FeaturePreview({ feature, imageFirst }: { feature: FeaturePreviewKind; imageFirst: boolean }) {
  const workspace = useDemoWorkspace(initialStates[feature]);
  const stage = useRef<HTMLDivElement>(null);
  const visibleComposer = workspace.state.windows.some(window => window.visible);

  useEffect(() => {
    function closeMenus(event: globalThis.PointerEvent) {
      if (!(event.target instanceof Element)) return;
      if (!stage.current?.contains(event.target) || !event.target.closest("[data-demo-menu], [data-menu-trigger]")) workspace.closeMenus();
    }
    document.addEventListener("pointerdown", closeMenus);
    return () => document.removeEventListener("pointerdown", closeMenus);
  }, [workspace]);

  return <div className={[
    demoCanvasClasses,
    featureCanvasClasses,
    featureBackgrounds[feature],
    imageFirst ? "lg:order-first" : "",
  ].join(" ")}
    data-feature={feature} data-appearance={workspace.state.appearance} data-demo-canvas="" data-feature-stage=""
    ref={stage} tabIndex={-1} role="group" aria-label={labels[feature]}>
    <div className={composerLayerClasses}>
      {workspace.state.windows.map(spec => <DemoWindow key={`${workspace.state.generation}-${spec.id}`} spec={spec} workspace={workspace} canvas={stage} featurePreview/>)}
    </div>
    {(feature === "activity" || workspace.state.islandOpen) && <ActivityIsland key={workspace.state.generation} workspace={workspace}/>}
    {(feature === "history" || workspace.state.historyOpen) && <HistoryPanel workspace={workspace}/>}
    {!visibleComposer && feature === "composer" && <button type="button" className={reopenClasses} onClick={() => workspace.addComposer()}>New composer</button>}
    <div className="absolute bottom-3 left-3 z-[3] rounded-[20px] bg-[#f7f4ecd9] px-[9px] py-[5px] text-[10px] leading-none text-[#544b40]">{feature === "activity" ? "Sample data · Select a task" : "Interactive preview · Sample data"}</div>
    <div className={stageToolsClasses}>
      {feature === "history" && !workspace.state.historyOpen && <IconButton icon="history" label="Show conversation history" onClick={() => workspace.patch({ historyOpen: true })}/>}
      <IconButton icon="reset" label={`Reset ${feature} preview`} onClick={workspace.reset}/>
    </div>
    {workspace.state.previewFile && <FilePreview file={workspace.state.previewFile} onClose={() => workspace.patch({ previewFile: null })}/>}
  </div>;
}
