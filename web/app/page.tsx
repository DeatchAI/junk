import InteractiveDemo from "@/components/interactive-demo";
import FeatureShowcase from "@/components/feature-showcase";

export default function Home() {
  return (
    <main>
      <section className="min-h-[78vh] sm:min-h-[88vh] flex flex-col items-center justify-center pt-[7rem] px-[1.5rem] sm:pt-[10rem] text-center gap-7 sm:gap-10">
        <p className="font-semibold text-base sm:text-xl tracking-wide flex items-center gap-2">
          <span className="text-base sm:text-xl"></span> Ergonomic AI agents
        </p>
        <h1 className="sick max-w-full text-[clamp(4.25rem,19vw,8rem)] leading-[0.82] tracking-[-0.035em] sm:leading-[0.94]">
          Cursor for <br />
          your <span className="">entire</span> macOS
        </h1>
        {/* <p className="text-gray-500 text-xl w-1/2 text-center mx-auto">
          Lorem ipsum dolor sit amet, consectetur adipisicing elit. Ut asperiores suscipit maiores?
        </p> */}
        {/* <button className="px-4 py-2 bg-black text-white rounded-xl cursor-pointer">
          <span className="mr-2"></span>
          Download for macOS
        </button> */}
        <section className="w-full max-w-[1160px] mx-auto -mt-12">
          <InteractiveDemo />
        </section>
      </section>
      <FeatureShowcase />
    </main>
  );
}
