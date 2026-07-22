import Image from "next/image"

export default function Navbar() {
    return (
        <div className="fixed top-0 left-0 right-0 z-50 flex justify-center pointer-events-none ">
          <nav className="pointer-events-auto relative flex items-center justify-between gap-6 sm:gap-10 bg-black text-white px-5 py-3 rounded-b-2xl shadow-xl border-x border-b border-white/10 w-auto">
            {/* Left flare */}
            <svg
              className="absolute top-0 right-full w-8 h-8 pointer-events-none"
              viewBox="0 0 16 16"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M 0 0 L 16 0 L 16 16 C 16 7.164 7.164 0 0 0 Z" fill="black" />
            </svg>

            {/* Right flare */}
            <svg
              className="absolute top-0 left-full w-8 h-8 pointer-events-none"
              viewBox="0 0 16 16"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M 16 0 L 0 0 L 0 16 C 0 7.164 7.164 0 16 0 Z" fill="black" />
            </svg>

            {/* Logo */}
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

            {/* Nav Links */}
            <div className="hidden md:flex items-center gap-6">
              <a href="#features" className="text-zinc-300 hover:text-white focus-visible:text-white focus-visible:outline-none tracking-tight font-light transition-colors">
                Features
              </a>
              <a href="#security" className="text-zinc-300 hover:text-white focus-visible:text-white focus-visible:outline-none tracking-tight font-light transition-colors">
                Security
              </a>
              <a href="#faq" className="text-zinc-300 hover:text-white focus-visible:text-white focus-visible:outline-none tracking-tight font-light transition-colors">
                FAQ
              </a>
              {/* <a href="#pricing" className="text-zinc-300 hover:text-white tracking-tight font-light transition-colors">
                Pricing
              </a> */}
            </div>

            {/* Download CTA */}
            <a
              href="#download"
              className="bg-white text-black text-xs font-semibold px-3 py-1.5 rounded-full flex items-center gap-1.5 hover:bg-zinc-200 focus-visible:bg-zinc-200 focus-visible:outline-none active:scale-95 transition-all"
            >
              
              <span>Download</span>
            </a>
          </nav>
        </div>
    )
}
