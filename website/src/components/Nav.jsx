import { useEffect, useState } from 'react'
import StrideLogo from './StrideLogo'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 40)
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-400 ${
        scrolled
          ? 'bg-bg-dark/90 backdrop-blur-xl shadow-[0_1px_0_rgba(255,255,255,0.06)]'
          : 'bg-transparent'
      }`}
    >
      <div className="max-w-[1400px] mx-auto px-6 py-4 flex items-center justify-between">
        <a href="#" className="flex items-center gap-3">
          <StrideLogo className="h-7 w-auto" />
          <span className="font-barlow font-bold text-lg tracking-[0.2em] text-white uppercase hidden sm:inline">
            Stride
          </span>
          <span className="hidden lg:inline text-[11px] tracking-[0.1em] text-white/30 font-light ml-2 border-l border-white/10 pl-4">
            AI-Powered Training Plans — Built for the Assault Runner
          </span>
        </a>

        <div className="flex items-center gap-8">
          <a href="#features" className="hidden md:inline text-[15px] font-medium text-white/40 hover:text-white transition-colors tracking-wide">
            Features
          </a>
          <a href="#how-it-works" className="hidden md:inline text-[15px] font-medium text-white/40 hover:text-white transition-colors tracking-wide">
            How It Works
          </a>
          <a href="#distances" className="hidden md:inline text-[15px] font-medium text-white/40 hover:text-white transition-colors tracking-wide">
            Distances
          </a>
        </div>
      </div>
    </nav>
  )
}
