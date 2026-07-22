"use client";

import InteractiveDemo from "@/components/interactive-demo";
import TypewriterPrompt from "@/components/typewriter-prompt";
import AgentSelectorDemo from "@/components/agent-selector-demo";
import { JitterTitle } from "@/components/jitter-title";
import { AppWindow, ArrowUp, BriefcaseBusiness, Code2, Globe2, Headphones, History, LockOpen, Maximize2, MessageSquarePlus, MousePointer, Paperclip, Plus, UserRound, X, ChevronUp } from "lucide-react";
import { useState } from "react";
import Image from "next/image";

const useCases = [
  {
    title: "Developers",
    description: "Hand off a code review, trace an error, run a command, or keep a task moving across your editor, terminal, and browser.",
    icon: Code2,
  },
  {
    title: "Browser work",
    description: "Research, navigate, and complete routine work in the Chrome profile you are already signed in to.",
    icon: Globe2,
  },
  {
    title: "macOS workflows",
    description: "Bring selected text and files into a task, then let an agent work across the apps and windows on your Mac.",
    icon: AppWindow,
  },
  {
    title: "Sales and support",
    description: "Turn account context, support threads, and product details into a grounded draft while you stay in control of what gets sent.",
    icon: Headphones,
  },
  {
    title: "Founders and operators",
    description: "Collect research, prepare a brief, and turn recurring busywork into a reusable workflow instead of another manual checklist.",
    icon: BriefcaseBusiness,
  },
  {
    title: "Everyday Mac work",
    description: "Ask from anywhere with a shortcut, attach the context in front of you, and let the task keep working in the notch.",
    icon: UserRound,
  },
];

const faqs = [
  {
    question: "What is Detach?",
    answer: "Detach is a macOS AI agent that lets you start work from the text, files, browser tabs, and apps already in front of you.",
  },
  {
    question: "Which AI agents can I use?",
    answer: "Detach can work with the local agents you already use, including supported signed-in CLI agents such as Codex, Claude Code, and Grok.",
  },
  {
    question: "Can Detach work in my signed-in browser?",
    answer: "Yes. Browser tasks can use your existing Chrome profile, so the agent can work with the sites and sessions you have explicitly connected.",
  },
  {
    question: "Can it control macOS apps?",
    answer: "Yes. Detach can give a task macOS capabilities for working across native apps, windows, controls, shortcuts, and files when you allow it.",
  },
  {
    question: "How do I start a task?",
    answer: "Select text or files and invoke Detach, or open its floating chat with the app shortcut. Your task can continue in the notch after the composer closes.",
  },
  {
    question: "Can I save repeat work?",
    answer: "Yes. Workflows and Quick Actions let you package a repeatable instruction with the capabilities it needs and launch it again in one step.",
  },
  {
    question: "Are credentials exposed to the AI?",
    answer: "No. Saved credentials remain in macOS Keychain. Secure fill requires your device approval and places a credential only in the verified login field.",
  },
  {
    question: "Do I have to use Detach credits?",
    answer: "No. Detach is designed to use the model subscriptions and local agent CLIs you already have, rather than adding a second hosted model plan.",
  },
  {
    question: "Can I see what an agent did?",
    answer: "Yes. Tasks keep structured activity and results, and sensitive access is recorded so you can review what happened and why.",
  },
  {
    question: "Is Detach only for coding?",
    answer: "No. Coding is one use case. Detach is built for browser work, operations, research, support, personal productivity, and the rest of your Mac workflow.",
  },
];

export default function Home() {
  const [showResponse, setShowResponse] = useState(false);

  const handleButtonClick = () => {
    setShowResponse(true);
    setTimeout(() => setShowResponse(false), 3000); // Hide after 3 seconds
  };
  return (
    <main className="">
      <section id="download" className="
      min-h-[78vh] sm:min-h-[88vh] max-md:min-h-0 flex flex-col items-center justify-center px-[1.5rem] 
      pt-32 max-md:pb-20 text-center gap-7">
        <p className="font-semibold text-base flex items-center gap-1">
          <span className=""></span>Ergonomic AI App
        </p>
        {/* <h1 className="sick max-w-full text-[clamp(4.25rem,19vw,6rem)] 
        leading-[0.82] sm:leading-[0.94] font-medium">
          

        </h1> */}

        <div className="relative z-10 flex w-full select-none flex-col items-center justify-center text-center 
        min-[768px]:mb-4 min-[768px]:scale-110 min-[1025px]:mb-6 min-[1025px]:scale-[1.15] min-[1280px]:mb-8 
        min-[1280px]:scale-[1.2] origin-center sick">
          <JitterTitle
            as="h1"
            className="m-0 apple text-center relative z-10 leading-[0.82] sm:leading-[0.94] font-medium
            text-[clamp(3rem,14vw,4.25rem)] md:text-[clamp(4.25rem,19vw,4rem)]"
          >
            Cursor for <br />
            <span className="flex items-center justify-center gap-3 leading-[0.7]">
              <span className="font-normal">your entire macOS</span>
            </span>
          </JitterTitle>
        </div>

        <p className="text-gray-500 text-xl max-md:w-full w-1/2 text-center mx-auto">
          Lorem ipsum dolor sit amet, consectetur adipisicing elit. Ut asperiores suscipit maiores?
        </p>
        <button className="px-4 py-2 bg-black text-white rounded-xl cursor-pointer">
          <span className="mr-2"></span>
          Download for macOS
        </button>
        <section className="w-full max-w-[1160px] mx-auto relative" aria-label="Detach workspace demo">
          <InteractiveDemo />
          {/* <img src="/wallpaper.webp" alt="demo-image" className="w-full h-full object-cover object-bottom
           absolute top-0 left-0 right-0 bottom-0 -z-10" /> */}
        </section>
      </section>

      <section className="container max-md:px-5 px-8">
        <JitterTitle
          as="p"
          className="text-center w-full max-md:mt-12 mt-20 max-md:pt-12 pt-20 max-md:text-5xl text-7xl sick flex items-center justify-center capitalize"
        >
          AI harness built for
        </JitterTitle>
        <JitterTitle
          as="p"
          className="text-center max-md:mb-10 mb-20 max-md:pb-6 pb-12 w-full max-md:text-5xl text-7xl sick flex items-center justify-center capitalize"
        >
          50 million{" "}
          <svg
            className="w-14 h-14 mb-2 ml-3 mr-2"
            viewBox="0 -10 256 335"
            fill="#000"
            aria-hidden="true"
          >
            <path d="M213.8 167.1c-.4-44.4 36.2-65.7 37.9-66.8-20.6-30.2-52.7-34.3-64.2-34.8-27.3-2.8-53.4 16.1-67.3 16.1-13.9 0-35.3-15.7-58-15.3-29.9.4-57.4 17.4-72.8 44.1-31 53.8-7.9 133.5 22.3 177.2 14.8 21.4 32.4 45.5 55.6 44.6 22.3-.9 30.7-14.4 57.6-14.4s34.5 14.4 58 14 38.3-21.8 53-43.3c16.7-24.8 23.6-48.9 24-50.1-.5-.2-46.1-17.7-46.5-70.2zM170.1 46.5c12.3-14.9 20.6-35.6 18.3-56.3-17.7.7-39.2 11.8-51.9 26.7-11.4 13.2-21.4 34.3-18.7 54.6 19.8 1.5 39.9-10.1 52.3-25z" />{" "}
          </svg>
          Mac users.
        </JitterTitle>
        <div className="grid gap-4 grid-cols-1 xl:grid-cols-3 items-stretch w-full max-md:h-auto h-[85vh]">

          <div className="marketing-card">
            <div className="card grow-1 flex flex-col max-md:h-auto max-md:p-4 p-8 h-40">
              <h1 className="max-md:text-2xl text-3xl sick">Code, Work & Automate.</h1>
              <p>Lorem, ipsum dolor sit amet consectetur adipisicing elit. adipisci in eligendi arcs qu</p>
            </div>
            <div className="grow dark-rich-bg w-full h-full max-md:mt-4 max-md:h-56 max-md:grow-0 px-5 py-4 flex items-center justify-center relative">
              {/* Response Box */}
              {showResponse && (
                <div className="absolute top-18 left-1/2 -translate-x-1/2 text-black bg-white px-4 py-2 rounded-lg 
                text-left text-[0.74rem] sm:text-[clamp(0.62rem,1vw,0.82rem)] shadow-lg z-20 animate-in fade-in 
                slide-in-from-top-2 duration-300 h-10 w-[90%]">
                  To try the agent, download Detach
                </div>
              )}

              <section
                className="relative overflow-hidden rounded-lg bg-[#ffffff] p-2.5 pb-12 text-left h-full max-md:max-h-none max-h-32 w-full flex flex-col text-black"
                aria-label="Detach floating chat window"
              >
                <button
                  className="absolute grid place-items-center border-0 p-0 bg-transparent text-[#929094] leading-none 
                  top-3 right-3 z-10"
                  type="button"
                  tabIndex={-1}
                  aria-label="Close floating chat"
                >
                  <X className="w-4 h-4 [stroke-width:1.45]" />
                </button>
                <TypewriterPrompt />
                <footer className="absolute flex items-center justify-between gap-3 left-[1rem] sm:left-[clamp(0.8rem,1.55vw,1.1rem)] right-[1rem] sm:right-[clamp(0.8rem,1.55vw,1.1rem)] bottom-[0.72rem] sm:bottom-[clamp(0.58rem,1vw,0.75rem)]" aria-hidden="true">
                  <div className="flex items-center gap-[0.42rem] sm:gap-[clamp(0.32rem,0.65vw,0.5rem)]">
                    <strong className="font-[430] text-[0.48rem] sm:text-[clamp(0.5rem,0.82vw,0.68rem)]">
                      Codex
                    </strong>
                    <ChevronUp className="text-[#7d7b80] [stroke-width:1.5] w-[0.45rem] sm:w-[clamp(0.48rem,0.75vw,0.6rem)] h-[0.45rem] sm:h-[clamp(0.48rem,0.75vw,0.6rem)]" />
                    <strong className="font-[430] text-[0.48rem] sm:text-[clamp(0.5rem,0.82vw,0.68rem)]">
                      GPT-5.6-Sol
                    </strong>
                    <ChevronUp className="text-[#7d7b80] [stroke-width:1.5] w-[0.45rem] sm:w-[clamp(0.48rem,0.75vw,0.6rem)] h-[0.45rem] sm:h-[clamp(0.48rem,0.75vw,0.6rem)]" />
                  </div>
                  <div className="flex items-center gap-3">
                    <Paperclip className="demo-attachment-trigger [stroke-width:1.6] w-4 h-4" />
                    <History className="[stroke-width:1.6] w-4 h-4" />
                    <MessageSquarePlus className="[stroke-width:1.6] w-4 h-4" />
                    <Maximize2 className="[stroke-width:1.6] w-4 h-4" />
                    <button
                      className="bg-orange-500 rounded-full p-1 hover:bg-orange-600 transition-colors"
                      tabIndex={-1}
                      onClick={handleButtonClick}
                    >
                      <ArrowUp className="[stroke-width:1.6] w-3 h-3 " />
                    </button>
                  </div>
                </footer>
              </section>
            </div>
          </div>

          <div className="marketing-card">
            <div className="card grow-1 flex flex-col max-md:h-auto max-md:p-4 p-8 h-40">
              <h1 className="max-md:text-2xl text-3xl sick">Your own subscriptions.</h1>
              <p>Lorem, ipsum dolor sit amet consectetur adipisicing elit. adipisci in eligendi arc</p>
            </div>
            <div className="grow dark-rich-bg w-full h-full max-md:mt-4 max-md:min-h-[23rem] max-md:grow-0 flex items-start justify-center py-8 relative">
              <AgentSelectorDemo />
            </div>
          </div>

          <div className="marketing-card">
            <div className="card grow-1 flex flex-col max-md:h-auto max-md:p-4 p-8 h-40">
              <h1 className="max-md:text-2xl text-3xl sick">Quick actions.</h1>
              <p>Lorem, ipsum dolor sit amet consectetur adipisicing elit. adipisci in?</p>
            </div>
            <div className="grow dark-rich-bg w-full h-full max-md:mt-4 max-md:h-64 max-md:grow-0 px-5 flex items-center justify-center relative">
              {/* <img src="https://aside.com/_next/static/media/banner.1ob9_piqf0xm6.webp?dpl=dpl_85UXzKU9SHrVUxVGamA6cg7HafjW" alt="" /> */}
              {/* <p className="bg-pink-400/50 p-1 text-pink-500">Lorem, ipsum dolor sit amet consectetur adipisicing elit. adipisci in eligendi arcs quisquam. Blanditiis, neque?</p> */}
              <p className="max-md:text-sm max-md:leading-5">
                Lorem ipsum dolor sit amet consectetur adipisicing elit. Repellat dolor officiis id, voluptatum aspernatur dolorum dolores eum ipsum distinctio modi fuga quia reprehenderit explicabo aut saepe necessitatibus, alias quisquam doloribus.
                <span className="bg-orange-400/60 text-orange-700 px-1 ink">
                  This long text will wrap to the next line, and the pink background
                  will wrap beautifully around each individual line instead of
                  looking like one giant solid
                </span>
              </p>
              <MousePointer className="absolute max-md:top-36 max-md:left-12 top-44 left-40 z-10 fill-black" />
              <div className="absolute max-md:top-28 max-md:right-1 top-36 right-1 rounded-lg bg-white flex items-center gap-1 max-md:text-[0.65rem] text-sm">
                <h1 className="hover:bg-orange-400 bg-white rounded-l-lg max-md:px-1.5 px-2.5 py-1">Chat</h1>
                <h1 className="hover:bg-orange-400 bg-white max-md:px-1.5 px-2.5 py-1">Remember this</h1>
                <h1 className="hover:bg-orange-400 bg-white rounded-r-lg max-md:px-1.5 px-2.5 py-1">Explain</h1>
              </div>
            </div>
          </div>

        </div>
      </section>

      <section id="security" className="container max-md:px-6 px-8 h-fit flex flex-col items-center max-md:pb-16 pb-24 pt-10">
        <JitterTitle
          as="p"
          className="text-center w-full max-md:mt-12 mt-20 max-md:pt-12 pt-20 max-md:text-5xl text-7xl sick flex items-center justify-center capitalize"
        >
          Secrets manager
        </JitterTitle>
        <JitterTitle
          as="p"
          className="text-center w-full max-md:text-5xl text-7xl sick flex items-center justify-center capitalize"
        >
          for agents
          <LockOpen className="w-14 h-14 ml-3" />
        </JitterTitle>
        <p className="mt-8 text-center max-md:w-full w-1/2">
          AI agents stop at login screen and ask you to log in every time. Aside lets agents sign in through autofill, without ever exposing your credentials to the AI.
        </p>
        <div className="flex w-full snap-x snap-mandatory gap-4 overflow-x-auto pb-3 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden md:gap-6 md:pl-6 md:overflow-visible md:pb-0 lg:grid lg:grid-cols-3 lg:px-6 my-16 md:my-28">
          <div className="shrink-0 snap-start w-[82vw] max-w-80 md:w-80 lg:w-auto">
            <div className="pointer-events-none relative h-80 w-full overflow-hidden rounded-lg bg-neutral-100 select-none md:h-64 lg:h-80 2xl:h-96">
              <img
                alt="Secrets stay invisible to AI"
                loading="eager"
                decoding="async"
                data-nimg="fill"
                className="object-cover"
                src="/demos/password.png"
                style={{
                  position: "absolute",
                  height: "100%",
                  width: "100%",
                  inset: 0,
                  color: "transparent"
                }}
              />
            </div>
            <div className="px-4 py-5">
              <p className="text-muted-foreground text-sm xl:text-base [&_span]:text-primary [&_span]:font-medium">
                <span>Secrets stay invisible to AI</span> Credentials are autofilled
                into websites, not exposed to the agent.
              </p>
            </div>
          </div>
          <div className="shrink-0 snap-start w-[82vw] max-w-80 md:w-80 lg:w-auto">
            <div className="pointer-events-none relative h-80 w-full overflow-hidden rounded-lg bg-neutral-100 select-none md:h-64 lg:h-80 2xl:h-96">
              <img
                alt="Human approval at the edge"
                loading="eager"
                decoding="async"
                data-nimg="fill"
                className="object-cover scale-120 object-[70%_40%]"
                src="/demos/touch.png"
                style={{
                  position: "absolute",
                  height: "100%",
                  width: "100%",
                  inset: 0,
                  color: "transparent"
                }}
              />
            </div>
            <div className="px-4 py-5">
              <p className="text-muted-foreground text-sm xl:text-base [&_span]:text-primary [&_span]:font-medium">
                <span>Human approval at the edge</span> Sensitive actions like payments,
                posts, and messages always wait for your confirmation.
              </p>
            </div>
          </div>
          <div className="shrink-0 snap-start w-[82vw] max-w-80 md:w-80 lg:w-auto">
            <div className="pointer-events-none relative h-80 w-full overflow-hidden rounded-lg bg-neutral-100 select-none md:h-64 lg:h-80 2xl:h-96">
              <img
                alt="A record of every access"
                loading="eager"
                decoding="async"
                data-nimg="fill"
                className="object-cover"
                src="/demos/image.png"
                style={{
                  position: "absolute",
                  height: "100%",
                  width: "100%",
                  inset: 0,
                  color: "transparent"
                }}
              />
            </div>
            <div className="px-4 py-5">
              <p className="text-muted-foreground text-sm xl:text-base [&_span]:text-primary [&_span]:font-medium">
                <span>A record of every access</span> Every credential use is logged, so
                you know exactly what the agent touched.
              </p>
            </div>
          </div>
          <div
            aria-hidden="true"
            className="w-1 shrink-0 snap-end md:-ml-4 md:w-6 lg:hidden"
          />
        </div>

        <div className="flex flex-col gap-6 p-0! md:flex-row w-full max-md:h-auto h-[70vh]">
          <div className="flex grow flex-col max-md:px-0 max-md:pt-8 p-8">
            <h3
              data-slot="heading"
              className="max-md:text-4xl text-5xl apple"
            >
              AI never sees your passwords, <br /> only fills them
            </h3>
            <div className="min-h-32 py-4 md:grow">
              <a
                role="button"
                tabIndex={0}
                data-slot="button"
                className="bg-orange-50 p-2 rounded-lg"
                data-lazzy-ref="lz-92aea28e-25"
              >
                Learn more
              </a>
            </div>
            <ul className="space-y-4">
              <li>
                <p className="text-sm xl:text-base text-primary font-medium underline">
                  Hardware-backed E2E encryption
                </p>
                <p className="text-muted-foreground text-sm xl:text-base">
                  <span
                    data-br="_r_4d_"
                    data-brr="0.4"
                    style={{
                      display: "inline-block",
                      verticalAlign: "top",
                      textDecoration: "inherit",
                      textWrap: "initial",
                      maxWidth: "449.2px"
                    }}
                  >
                    Your data is full encrypted in local and protected by Secure
                    Enclave.
                  </span>
                </p>
              </li>
              <li>
                <p className="text-sm xl:text-base text-primary font-medium underline">
                  Scoped access and audit log
                </p>
                <p className="text-muted-foreground text-sm xl:text-base">
                  <span
                    data-br="_r_4e_"
                    data-brr="0.4"
                    style={{
                      display: "inline-block",
                      verticalAlign: "top",
                      textDecoration: "inherit",
                      textWrap: "initial",
                      maxWidth: "391.2px"
                    }}
                  >
                    Give the agent access only to what each task needs. See what it
                    used, when, and why.
                  </span>
                </p>
              </li>
            </ul>
          </div>
          <div className="relative hidden md:flex aspect-4/3 w-full items-center justify-center bg-mist-800 sm:max-lg:hidden md:aspect-square md:h-full 
          lg:aspect-auto lg:h-auto lg:w-[50%] lg:shrink-0 lg:self-stretch">
            <img
              alt="Password Manager"
              loading="eager"
              decoding="async"
              data-nimg="fill"
              className="object-cover"
              src="/demos/secret.png"
              style={{
                position: "absolute",
                height: "100%",
                width: "100%",
                inset: 0,
                color: "transparent"
              }}
            />
          </div>
        </div>

      </section>

      <section className="mx-auto w-full max-w-[1240px] px-6 pb-28 pt-24 sm:px-8 sm:pb-36 sm:pt-32" aria-labelledby="use-cases-heading">
        <header className="mx-auto max-w-[680px] text-center">
          <JitterTitle className="max-md:text-5xl text-7xl apple">
             Built for the  <br/> work you do on Mac
          </JitterTitle>
          <p className="mx-auto mt-6 max-w-[610px] text-[1.05rem] leading-[1.45] text-neutral-500 sm:text-[1.2rem]">
            From code and browser research to selected files and repeatable workflows,
            Detach gives the AI you already use a better way to work on your Mac.
          </p>
        </header>

        <div className="mt-14 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {useCases.map(({ title, description, icon: Icon }) => (
            <article key={title} className="min-h-[20.8rem] rounded-[2rem] bg-[#f6f6f6] p-10 sm:p-[2.5rem]">
              <span className="grid size-16 place-items-center rounded-full bg-white text-black">
                <Icon className="size-6 stroke-[1.65]" aria-hidden="true" />
              </span>
              <h3 className="apple mt-7 text-[2rem] leading-[0.93] tracking-[-0.055em]">
                {title}
              </h3>
              <p className="mt-5 max-w-[18rem] text-[1rem] leading-[1.45] text-neutral-500">
                {description}
              </p>
            </article>
          ))}
        </div>
      </section>

      <section className="mx-auto w-full max-w-[1080px] px-6 pb-32 pt-20 sm:px-8 sm:pb-44 sm:pt-28" aria-labelledby="faq-heading">
        <header className="mx-auto max-w-[720px] text-center">
         <JitterTitle className="max-md:text-5xl text-7xl apple">
          Frequently asked questions
         </JitterTitle>
          <p className="mx-auto mt-6 max-w-[630px] text-[1.05rem] leading-[1.45] text-neutral-500 sm:text-[1.2rem]">
            Everything you need to know before giving Detach a place in your daily Mac workflow.
          </p>
        </header>

        <div className="mt-14 grid grid-cols-1 gap-x-5 gap-y-4 md:grid-cols-2">
          {faqs.map(({ question, answer }) => (
            <details key={question} className="group rounded-[1.25rem] bg-[#f6f6f6] px-5 py-4">
              <summary className="flex cursor-pointer list-none items-center gap-5 text-[0.94rem] font-medium leading-snug marker:content-none [&::-webkit-details-marker]:hidden">
                <span className="grid size-5 shrink-0 place-items-center">
                  <Plus className="size-5 stroke-[1.7] group-open:hidden" aria-hidden="true" />
                  <span className="hidden h-px w-4 bg-black group-open:block" aria-hidden="true" />
                </span>
                {question}
              </summary>
              <p className="ml-10 mt-4 max-w-[29rem] text-[0.92rem] leading-[1.5] text-neutral-500">
                {answer}
              </p>
            </details>
          ))}
        </div>
      </section>

      <footer className="relative mt-10 bg-black px-6 pt-16 text-white sm:px-8 sm:pt-20">
        <span className="absolute -top-10 left-0 h-10 w-[clamp(2.5rem,10vw,9rem)] bg-black" aria-hidden="true" />
        <svg className="pointer-events-none absolute -top-10 left-[clamp(2.5rem,10vw,9rem)] size-10 rotate-180" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M 0 0 L 16 0 L 16 16 C 16 7.164 7.164 0 0 0 Z" fill="black" />
        </svg>
        <span className="absolute -top-10 right-0 h-10 w-[clamp(2.5rem,10vw,9rem)] bg-black" aria-hidden="true" />
        <svg className="pointer-events-none absolute -top-10 right-[clamp(2.5rem,10vw,9rem)] size-10 rotate-180" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path d="M 16 0 L 0 0 L 0 16 C 0 7.164 7.164 0 16 0 Z" fill="black" />
        </svg>

        <div className="mx-auto grid w-full max-w-[1080px] gap-14 pb-20 md:grid-cols-[minmax(0,1.45fr)_minmax(0,0.7fr)_minmax(0,0.7fr)] md:gap-10">
          <div className="max-w-[25rem]">
            <p className="flex items-center gap-2 text-sm font-semibold">
              <a href="#" className="flex items-center gap-0 hover:opacity-90 focus-visible:opacity-90 focus-visible:outline-none transition-opacity">
                            <Image
                              src="/icon.svg"
                              alt="Detach Logo"
                              width={40}
                              height={40}
                              className="rounded-md"
                              priority
                            />
                            <span className="text-xl tracking-tight font-semibold">Detach</span>
                          </a>
               {/* <span className="font-normal text-white/45">macOS AI agent</span> */}
            </p>
            {/* <h2 className="apple mt-7 text-[clamp(2.6rem,4vw,4rem)] leading-[0.9] tracking-[-0.06em]">
              Your agents, <br /> your entire Mac.
            </h2> */}
            <p className="mt-5 text-[0.95rem] leading-[1.5] text-white/55">
              Start a task from the work in front of you, then let Detach keep it moving across your browser, files, and apps.
            </p>
            <a href="#download" className="mt-7 inline-flex items-center gap-2 rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-black transition-colors hover:bg-white/85 focus-visible:bg-white/85 focus-visible:outline-none">
              <span aria-hidden="true"></span> Download for macOS
            </a>
            <p className="mt-7 text-xs text-white/35">© {new Date().getFullYear()} Detach. Built for the desktop.</p>
          </div>

          <nav aria-label="Explore Detach">
            <p className="text-sm font-medium text-white/45">Explore</p>
            <ul className="mt-5 space-y-3 text-sm text-white/80">
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#use-cases-heading">Use cases</a></li>
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#security">Security</a></li>
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#faq-heading">FAQ</a></li>
            </ul>
          </nav>

          <nav aria-label="Capabilities">
            <p className="text-sm font-medium text-white/45">Capabilities</p>
            <ul className="mt-5 space-y-3 text-sm text-white/80">
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#use-cases-heading">Browser work</a></li>
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#use-cases-heading">macOS automation</a></li>
              <li><a className="transition-colors hover:text-[#ff7900] focus-visible:text-[#ff7900] focus-visible:outline-none" href="#security">Protected credentials</a></li>
            </ul>
          </nav>
        </div>

        <p className="apple mx-auto w-full mt-40 max-w-[1320px] select-none text-center max-md:text-[5rem] text-[clamp(6rem,21vw,19rem)] leading-0 tracking-[-0.09em]
         text-orange-500" aria-hidden="true">
          Detach
        </p>
      </footer>

    </main>
  );
}
