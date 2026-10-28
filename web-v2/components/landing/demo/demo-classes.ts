export const demoCanvasClasses = `
  relative isolate overflow-hidden
  border-0 bg-[#d3d3d3] text-left text-[color:var(--app-fg)]
  [font-family:-apple-system,BlinkMacSystemFont,Segoe_UI,sans-serif] font-normal
  tracking-[-.015em] antialiased
  [--app-bg:#0e0e0e] [--app-fg:#f3f3f3] [--app-muted:#959595]
  [--app-line:#ffffff15] [--app-control:#ffffff0d] [--app-hover:#ffffff16]
  [--app-pill:#262626] [--app-tray:#090909] [--app-menu:#101010]
  [--app-button:#f7f7f7] [--app-button-fg:#080808]
  [--app-logo-filter:grayscale(1)_brightness(0)_invert(1)]
  data-[appearance=light]:[--app-bg:#fdfdfd]
  data-[appearance=light]:[--app-fg:#222]
  data-[appearance=light]:[--app-muted:#777]
  data-[appearance=light]:[--app-line:#00000014]
  data-[appearance=light]:[--app-control:#00000006]
  data-[appearance=light]:[--app-hover:#0000000c]
  data-[appearance=light]:[--app-pill:#ededed]
  data-[appearance=light]:[--app-tray:#f4f4f4]
  data-[appearance=light]:[--app-menu:#fdfdfd]
  data-[appearance=light]:[--app-button:#171717]
  data-[appearance=light]:[--app-button-fg:#fff]
  data-[appearance=light]:[--app-logo-filter:grayscale(1)_brightness(0)]
  before:pointer-events-none before:absolute before:inset-0 before:z-[-1]
  before:bg-cover before:content-['']
  [&_button]:[font:inherit] [&_button]:[letter-spacing:inherit]
  [&_button]:cursor-pointer [&_button]:[-webkit-tap-highlight-color:transparent]
  [&_button:disabled]:cursor-default
  [&_button:disabled:not([data-send-button])]:opacity-[.35]
  [&_button:focus-visible]:outline-[1.5px]
  [&_button:focus-visible]:[outline-color:var(--app-muted)]
  [&_button:focus-visible]:outline-offset-[3px]
  [&_input]:[font:inherit] [&_input]:[letter-spacing:inherit]
  [&_input:focus-visible]:outline-[1.5px]
  [&_input:focus-visible]:[outline-color:var(--app-muted)]
  [&_input:focus-visible]:outline-offset-[3px]
  [&_button_svg]:shrink-0
  [&_[data-provider-logo]]:shrink-0 [&_[data-provider-logo]]:object-contain
`;

export const composerLayerClasses = "pointer-events-none absolute inset-0 z-[5]";

export const productSectionClasses = `
  mx-auto mt-[52px] w-full max-w-[1280px] px-[clamp(20px,4.5vw,64px)]
  max-[600px]:mt-10 max-[600px]:px-5
`;

export const productCanvasClasses = `
  h-[clamp(510px,52vw,660px)] rounded-[4px]
  max-[800px]:h-[560px] max-[600px]:h-[530px]
  before:bg-[url('/demo-bgs/10.png')]
`;

export const demoCaptionClasses = `
  mt-3 flex justify-between gap-4 text-[11px] leading-[1.6]
  text-[color:var(--page-muted)] max-[600px]:mt-[13px]
  max-[600px]:flex-col max-[600px]:gap-1.5 max-[600px]:text-[10px]
  [&_p]:m-0 [&_p>span]:px-[7px] [&_p>span]:opacity-50
  [&_kbd]:[font:inherit] [&_kbd]:text-[color:var(--page-fg)]
  [&>span]:whitespace-nowrap [&>span]:text-[11px] [&>span]:opacity-70
  max-[600px]:[&_p]:min-h-8 max-[600px]:[&>span]:text-[9px]
`;

export const featureCanvasClasses = `
  mx-3 mb-3 mt-0 h-[min(62svh,520px)] min-h-[360px] rounded-[3px]
  lg:mt-3 lg:h-auto lg:min-h-[calc(100svh_-_24px)]
  max-[600px]:min-h-[520px]
  [--attention-max-height:calc(100svh_-_100px)]
  max-lg:[--attention-max-height:min(380px,50svh)]
  before:bg-center
  [&_[data-activity-island][data-expanded=true]]:w-[min(374px,calc(85%_-_15.3px))]
  [&_[data-history-panel]]:w-[min(306px,calc(85%_-_17px))]
`;

export const workspaceClasses = ` scale-80
  pointer-events-auto absolute z-auto flex max-h-[calc(100%_-_24px)]
  cursor-grab touch-none flex-col drop-shadow-[0_12px_20px_#0000001c]
  active:cursor-grabbing
  [transform:translate(calc(-50%_+_var(--drag-x,0px)),var(--drag-y,0px))]
  [&_[data-no-drag]]:cursor-text [&_[data-no-drag]]:select-text
`;

export const reopenClasses = `
  absolute bottom-6 left-1/2 z-[4] flex -translate-x-1/2 items-center gap-2
  whitespace-nowrap rounded-lg border [border-color:var(--app-line)]
  [background-color:var(--app-bg)] px-3 py-[9px] text-[11px]
  text-[color:var(--app-fg)]
  shadow-[0_3px_12px_#00000012]
  [&_span]:ml-3 [&_span]:text-[9px] [&_span]:text-[color:var(--app-muted)]
`;

export const stageToolsClasses = `
  absolute right-3 bottom-3 z-[4] flex gap-[3px]
  [&>button]:grid [&>button]:size-7 [&>button]:place-items-center
  [&>button]:rounded-full [&>button]:border-0 [&>button]:bg-[#ffffff9e]
  [&>button]:p-0 [&>button]:text-[#707070]
  [&>button:hover]:bg-white
  max-[600px]:right-[9px] max-[600px]:bottom-[10px]
`;

export const composerClasses = {
  followUps: `
    relative mb-[14px] shrink-0 pl-4
    max-[600px]:mb-2.5 max-[600px]:pl-2.5
  `,
  followUpNumbers: "flex max-h-[60px] flex-wrap gap-[6px] overflow-y-auto",
  followUpButton: `
    h-[25px] min-w-[28px] rounded-lg border-[.7px]
    [border-color:var(--app-line)] [background-color:var(--app-bg)] px-2
    !text-xs font-medium text-[color:var(--app-muted)]
    aria-[pressed=true]:text-[color:var(--app-fg)]
    aria-[pressed=true]:[border-color:color-mix(in_srgb,var(--app-fg)_18%,transparent)]
  `,
  response: `
    mb-3 rounded-md border-[.5px] [border-color:var(--app-line)]
    [background-color:var(--app-bg)] px-[10px] pb-[13px]
    max-[600px]:mb-2.5 max-[600px]:p-[14px]
  `,
  responseCompact: "mb-3 border-0 bg-transparent p-0",
  responseBody: `
    mt-3 mb-4 max-h-[132px] overflow-y-auto whitespace-pre-wrap
    [overflow-wrap:anywhere] text-[14px] font-normal leading-[1.5]
    tracking-[-.016em] max-[600px]:max-h-[120px] max-[600px]:text-[13px]
  `,
  activitySummary: "flex items-center gap-[7px] bg-transparent p-0 !text-[10px] text-[color:var(--app-muted)]",
  copyButton: "flex items-center gap-[6px] border-0 bg-transparent p-0 !text-[10px] text-[color:var(--app-muted)]",
  spinner: `
    inline-block size-[9px] shrink-0 animate-spin rounded-full border
    border-current border-r-transparent border-t-transparent
    motion-reduce:animate-none
  `,
  composer: `
    relative shrink-0 rounded-md border-[.7px] [border-color:var(--app-line)]
    [background-color:var(--app-bg)] px-[10px] pt-[10px] pb-[11px]
    max-[600px]:px-[14px] max-[600px]:pt-[17px] max-[600px]:pb-[10px]
  `,
  dragHandle: `
    absolute top-0 left-1 right-[75px] h-[11px]
    touch-none cursor-grab rounded-tl-xl active:cursor-grabbing
  `,
  revision: `
    -mt-1 mb-[15px] flex items-center justify-between gap-3 pr-[69px]
    text-[11px] text-[color:var(--app-muted)]
    [&>span]:flex [&>span]:items-center [&>span]:gap-[5px]
    [&_button]:border-0 [&_button]:bg-transparent [&_button]:p-0
  `,
  windowControls: `
    absolute top-[17px] right-[17px] flex gap-[6px]
    max-[600px]:top-[14px] max-[600px]:right-3 max-[600px]:gap-px
  `,
  controlButton: `
    grid size-[26px] shrink-0 place-items-center rounded-md border-0
    bg-transparent p-0 text-[color:var(--app-muted)]
    hover:[background-color:var(--app-hover)]
  `,
  toolbarRightButton: `
    grid size-[26px] shrink-0 place-items-center rounded-md border-0
    bg-transparent p-0 text-[color:var(--app-muted)]
    hover:[background-color:var(--app-hover)] max-[600px]:size-[29px]
  `,
  draftMedia: "mb-[14px] pr-[65px]",
  editorLine: `
    min-h-[52px] max-h-[130px] cursor-text overflow-y-auto pb-3
    [overflow-wrap:anywhere] text-[14px] leading-[1.5]
    text-[color:var(--app-fg)] max-[600px]:min-h-16 max-[600px]:text-[13px]
    data-[has-media=false]:pr-[67px] max-[600px]:data-[has-media=false]:pr-14
  `,
  editor: `
    block min-w-[1ch] min-h-[1.5em] cursor-text whitespace-pre-wrap
    outline-none select-text empty:before:content-[attr(data-placeholder)]
    empty:before:pointer-events-none empty:before:text-[color:var(--app-muted)]
    focus-visible:outline-[1.5px] focus-visible:[outline-color:var(--app-muted)]
    focus-visible:outline-offset-[3px]
  `,
  caretMenuAnchor: `
    absolute top-[45px] left-[17px] z-[35] h-0 w-0 cursor-default
    text-[12px] leading-normal
  `,
  toolbar: "mt-px flex min-h-[26px] items-center justify-between",
  agentControls: "flex items-center gap-1",
  toolbarRight: "flex items-center gap-[9px] max-[600px]:gap-2",
  sendButton: `
    ml-0.5 grid size-6 shrink-0 place-items-center rounded-full border-0 p-0
    [background-color:var(--app-button)] text-[color:var(--app-button-fg)]
    hover:[background-color:var(--app-button)] hover:opacity-[.85]
    disabled:opacity-[.33] max-[600px]:size-[26px]
  `,
  menuAnchor: "relative",
  branchSwitcher: `
    flex items-center gap-px text-[10px] tabular-nums
    text-[color:var(--app-muted)]
    [&>button]:h-[22px] [&>button]:w-[17px]
    [&>span]:whitespace-nowrap [&>span]:px-[3px]
  `,
  projectBar: `
    mx-[14px] mt-[-1px] h-[33px] shrink-0 rounded-b-xl border-[.5px]
    [border-color:var(--app-line)] border-t-0
    [background-color:var(--app-tray)] px-3 py-[3px]
  `,
  projectButton: `
    flex h-[26px] items-center gap-[7px] border-0 bg-transparent px-0.5
    !text-xs text-[color:var(--app-muted)] hover:text-[color:var(--app-fg)]
    [&>svg:last-child]:ml-px
  `,
  expandedHistory: `
    mb-[10px] h-[285px] min-h-[60px] overflow-y-auto rounded-xl border-[.5px]
    [border-color:var(--app-line)] [background-color:var(--app-bg)] p-[14px]
    max-[600px]:h-[252px] max-[600px]:p-3
  `,
  expandedPrompt: `
    mb-4 ml-9 whitespace-pre-wrap rounded-[9px]
    [background-color:var(--app-control)] px-3 py-[10px]
    text-[12px] leading-[1.5] text-[color:var(--app-fg)]
  `,
  expandedEmpty: "p-[10px] text-[12px] text-[color:var(--app-muted)]",
  island: `
    absolute top-1/2 right-0 z-[10] w-[54.4px] -translate-y-1/2 origin-right scale-80 rounded-l-[19px]
    [background-color:var(--app-bg)] text-[color:var(--app-fg)]
    shadow-[0_7px_20px_#0000000a] transition-[width] duration-[220ms]
    motion-reduce:transition-none
    max-[600px]:w-[37.4px]
  `,
  islandExpanded: `
    w-[306px] px-3 pt-[10px] pb-[14px]
    max-[600px]:w-[min(297.5px,calc(85%_-_15.3px))]
  `,
  islandCollapsed: `
    flex h-[94px] w-full flex-col items-center justify-center gap-3
    border-0 bg-transparent p-0 text-[color:var(--app-fg)]
    max-[600px]:h-[62px] max-[600px]:gap-[7px]
    [&>span]:grid [&>span]:h-[19px] [&>span]:min-w-[21px]
    [&>span]:place-items-center [&>span]:rounded-lg
    [&>span]:[background-color:var(--app-button)] [&>span]:px-[6px]
    [&>span]:text-[10px] [&>span]:font-medium
    [&>span]:text-[color:var(--app-button-fg)]
  `,
  taskList: "max-h-[270px] overflow-y-auto [scrollbar-width:thin]",
  taskRow: "flex min-h-[60px] items-center gap-[6px] py-0 pr-0.5 pl-[6px]",
  taskLabel: `
    flex min-w-0 flex-1 items-center gap-[10px] border-0 bg-transparent p-0
    text-left text-[color:var(--app-fg)] [&>span]:min-w-0
    [&_strong]:block [&_strong]:overflow-hidden [&_strong]:text-ellipsis
    [&_strong]:whitespace-nowrap [&_strong]:text-[13px] [&_strong]:font-medium
    [&_small]:mt-1 [&_small]:flex [&_small]:items-center [&_small]:gap-[5px]
    [&_small]:text-[11px] [&_small]:text-[color:var(--app-muted)]
    [&_small>b]:font-normal [&_small>span:last-child]:max-w-[152px]
    [&_small>span:last-child]:overflow-hidden [&_small>span:last-child]:text-ellipsis
    [&_small>span:last-child]:whitespace-nowrap
    max-[600px]:[&_small>span:last-child]:max-w-[130px]
  `,
  taskActionButton: `
    grid size-[26px] shrink-0 place-items-center rounded-full border-0 p-0
    [background-color:var(--app-control)] text-[color:var(--app-muted)]
    hover:[background-color:var(--app-hover)]
  `,
} as const;
