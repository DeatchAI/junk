import Image from "next/image";

const browserTasks = [
  {
    title: "Signing in",
    description:
      "Detach signs in and works across your dashboards and internal tools.",
    prompt: "Get my paystubs for this month",
    image: "/demos/signin.png",
    gradient:
      "[background:linear-gradient(142deg,#f7d6e9_0%,#f8e9dc_47%,#fff3e7_100%)]",
    orb: "bg-[rgba(255,121,0,0.2)]",
    imagePosition: "",
  },
  {
    title: "Communications",
    description:
      "Detach handles messages, replies, and follow-ups in your signed-in accounts.",
    prompt: "Schedule a meeting with the sales lead",
    image: "/demos/x-dms.png",
    gradient:
      "[background:linear-gradient(145deg,#d6f1f5_0%,#cdebef_46%,#e3f4ea_100%)]",
    orb: "bg-[rgba(67,91,255,0.2)]",
    imagePosition: "object-[-1%_1%]",
  },
  {
    title: "Issue tracking",
    description:
      "Detach turns reports into actionable GitHub issues without opening another app.",
    prompt: "Create an issue from this crash report",
    image: "/demos/github-issue.png",
    gradient:
      "[background:linear-gradient(145deg,#d9f3df_0%,#dff4e4_45%,#eef6d9_100%)]",
    orb: "bg-[rgba(44,184,118,0.22)]",
    imagePosition: "object-[-15%_1%]",
  },
] as const;

export default function BrowserAutomationShowcase() {
  return (
    <section
      id="browser-automation"
      className="mx-auto w-[calc(100%_-_0.5rem)] max-w-[1350px] md:w-[calc(100%_-_0.75rem)]"
      aria-label="Detach capabilities"
    >
      {/* <div className="px-6 pt-[4.5rem] pb-[3.75rem] md:px-20 md:pt-24 md:pb-20 xl:pt-40 
      xl:pb-28 flex flex-col items-center gap-5">
        <h2 id="browser-automation-heading" className="text-8xl sick text-center">
          Detached
        </h2>
        <p className="mx-auto max-w-2xl text-xl leading-[1.52] font-normal tracking-[-0.012em] text-[#171717]
        text-center">
          Unlike other AI agents that rely on integrations, Detach uses websites
          and signed-in accounts directly, just like you do. That means you can
          ask it to handle the browser task in front of you whenever you need.
          The only wall is your imagination.
        </p>
      </div> */}

      {/* <div className="flex w-full flex-col gap-12 text-start md:gap-20 lg:gap-28">
        <div className="mx-3 flex flex-col items-center gap-8 overflow-hidden rounded-2xl soft-bg sm:mx-6 md:mx-14 md:flex-row md:items-center md:gap-14">
          <div className="flex h-full w-full flex-col items-start px-6 py-8 md:order-1 md:flex-[0_0_28%] md:justify-end md:pl-12 md:pr-0 md:py-12">
            <div className="apple text-8xl md:max-w-85">
              Coding,
            </div>
            <div className="text-mkt-p1 mt-5 md:max-w-87.5">
              From a focused feature to a complex refactor, Detach can work through
              your codebase, report progress as it goes, and leave a verified result.
            </div>
          </div>
          <div className="relative w-full md:max-w-none md:flex-[0_0_72%] md:order-2">
            <FloatingChatDemo kind="coding" />
          </div>
        </div>
        <div className="mx-3 flex flex-col items-center gap-8 overflow-hidden rounded-2xl soft-bg sm:mx-6 md:mx-14 md:flex-row-reverse md:items-center md:gap-8 lg:gap-20">
          <div className="flex h-full w-full flex-col items-start px-6 py-8 md:order-1 md:flex-[0_0_28%] md:justify-start md:pl-0 md:pr-12 md:py-12">
            <div className="apple text-8xl md:max-w-85 leading-20">
              Browser Use,
            </div>
            <div className="text-mkt-p1 mt-5 md:max-w-87.5">
              Detach works in the browser you are already signed in to. Sensitive
              credentials stay protected on your Mac and it pauses where approval matters.
            </div>
          </div>
          <div className="relative w-full md:max-w-none md:flex-[0_0_72%] md:order-2">
            <FloatingChatDemo kind="browser" />
          </div>
        </div>

        <div className="mx-3 flex flex-col items-center gap-8 overflow-hidden rounded-2xl soft-bg sm:mx-6 md:mx-14 md:flex-row md:items-center md:gap-14">
          <div className="flex h-full w-full flex-col items-start px-6 py-8 md:flex-[0_0_28%] md:justify-end md:pl-12 md:pr-0 md:py-12">
            <div className="apple text-8xl md:max-w-85 leading-20">
              macOS,
            </div>
            <div className="text-mkt-p1 mt-5 md:max-w-87.5">
              Detach moves through your desktop with the same care as you do—reading context, drafting changes, and stopping for approval before it acts.
            </div>
          </div>
          <div className="relative w-full md:max-w-none md:flex-[0_0_72%]">
            <FloatingChatDemo kind="macos" />
          </div>
        </div>
       
      </div> */}


      <div className="snap-x snap-mandatory scroll-px-6 overflow-x-auto pb-24 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden lg:overflow-visible lg:px-6 xl:pb-32">
        <div className="flex w-max gap-6 px-6 md:px-8 lg:grid lg:w-auto lg:grid-cols-3 lg:gap-6 lg:px-0">
          {browserTasks.map((task) => (
            <article
              className="group w-[min(84vw,24rem)] shrink-0 snap-start lg:w-auto"
              key={task.title}
            >
              <div
                className={`relative h-[clamp(19rem,34vw,24rem)] overflow-hidden bg-black/5
                rounded-[0.55rem]`}
                aria-hidden="true"
              >
                <div className="absolute -top-[28%] -left-[22%] -z-10 aspect-square w-[50%] rounded-full bg-white/90 opacity-[0.78] 
                blur-[2.5rem]" />
                <div
                  className={`absolute -right-[25%] -bottom-[30%] -z-10 aspect-square w-[70%] rounded-full opacity-[0.78] 
                    blur-[2.5rem] ${task.orb}`}
                />
                <div className="absolute top-[6.2rem] right-4 left-4 z-30 min-h-10 rounded-md border
                 border-black/[0.06] bg-white/[0.94] px-4 py-[0.82rem] text-base leading-[1.24] 
                 font-medium tracking-[-0.018em] shadow-[0_0.5rem_1.4rem_rgba(51,37,30,0.045)]">
                  {task.prompt}
                </div>
                <div className="absolute top-[10.75rem] -right-[4%] left-[9%] z-20 h-[65%] translate-y-0 overflow-hidden
                bg-white shadow-[0_1.2rem_3rem_rgba(40,32,28,0.11)] transition-transform duration-500 
                ease-[cubic-bezier(0.22,1,0.36,1)] motion-reduce:transition-none group-hover:-translate-y-1">
                  <Image
                    src={task.image}
                    alt=""
                    fill
                    sizes="(min-width: 1024px) 420px, (min-width: 640px) 416px, 82vw"
                    loading="eager"
                    className={` object-contain ${task.imagePosition}`}
                  />
                </div>
              </div>
              <p className="m-0 px-4 pt-[1.2rem] text-[clamp(0.92rem,1.12vw,1rem)] leading-[1.45] text-black/[0.56]">
                <strong className="font-medium text-[#171717]">
                  {task.title}
                </strong>{" "}
                {task.description}
              </p>
            </article>
          ))}
          <div className="w-2 shrink-0 lg:hidden" aria-hidden="true" />
        </div>
      </div>
    </section>
  );
}
