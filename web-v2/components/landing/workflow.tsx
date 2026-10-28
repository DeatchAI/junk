import { Arrow } from "./shared";
import { FeaturePreview } from "./demo/feature-preview";
import styles from "./workflow.module.css";

const features = [
  {
    id: "composer",
    label: "Floating composer",
    title: "Start a task from anywhere.",
    description: "Bring your agents with you across your Mac. Choose a project, add context, and start working without leaving what you’re doing.",
    imageFirst: false,
  },
  {
    id: "activity",
    label: "Activity notch",
    title: "Keep an eye on the work.",
    description: "Your running tasks stay close at the edge of your screen. Check their progress and return to a conversation when you need to.",
    imageFirst: true,
  },
  {
    id: "history",
    label: "History notch",
    title: "Pick up where you left off.",
    description: "Find conversations from your supported agents in one place. Search your history and return to the thread you need.",
    imageFirst: false,
  },
] as const;

export function Workflow() {
  return <section className="page-width pb-24 md:pb-32" id="how-it-works" aria-labelledby="workflow-title">
    <h2 className="sr-only" id="workflow-title">Three ways to work with your agents</h2>
    <div className="space-y-5 md:space-y-8">
      {features.map(feature => <article key={feature.id} className={`grid min-h-[100svh] overflow-hidden rounded-sm bg-surface ${feature.imageFirst ? "lg:grid-cols-[0.62fr_0.38fr]" : "lg:grid-cols-[0.38fr_0.62fr]"}`}>
        <div className="flex flex-col items-start justify-center px-7 py-12 md:px-10 lg:py-16">
          <p className="mb-5 text-xs text-muted">{feature.label}</p>
          <h3 className="max-w-xs text-3xl gothic md:text-[30px]">{feature.title}</h3>
          <p className="mt-4 max-w-xs text-sm leading-6 text-muted">{feature.description}</p>
          <a className={`${styles.accentLink} mt-7 inline-flex items-center gap-2 text-sm transition-opacity hover:opacity-70`} href="#film">Open the full demo <Arrow /></a>
        </div>
        <FeaturePreview feature={feature.id} imageFirst={feature.imageFirst} />
      </article>)}
    </div>
  </section>;
}
