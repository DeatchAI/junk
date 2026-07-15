import Image from "next/image";

export default function Home() {
  return (
    <div className="flex flex-col items-center justify-center gap-6 h-fit py-40">
      <p className="flex items-center"><span className="text-lg">&nbsp;</span> Ergonomic AI Agents App</p>
      <h1 className="text-8xl sick text-center">
        Detached coding, <br />
        <span className="font-light text-zinc-500">automation</span> & work.
      </h1>
      <div className="border-2 border-zinc-400/20 overflow-hidden mt-12 rounded-3xl">
        <Image src="/app.png" width={1024} height={1024} alt=""/>
      </div>
    </div>
  );
}


