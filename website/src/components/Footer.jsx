import StrideLogo from './StrideLogo'

export default function Footer() {
  return (
    <footer className="py-10 bg-bg-dark border-t border-white/[0.06]">
      <div className="max-w-[1400px] mx-auto px-6">
        <div className="flex flex-col md:flex-row items-center justify-between gap-6">
          <div className="flex items-center gap-3">
            <StrideLogo className="h-5 w-auto" color="rgba(255,255,255,0.2)" />
            <span className="font-barlow font-bold text-sm tracking-[0.15em] text-white/20 uppercase">
              Stride
            </span>
          </div>

          <div className="flex items-center gap-8">
            <a href="#features" className="text-[12px] text-white/20 hover:text-white/50 transition-colors">Features</a>
            <a href="#how-it-works" className="text-[12px] text-white/20 hover:text-white/50 transition-colors">How It Works</a>
            <a href="#distances" className="text-[12px] text-white/20 hover:text-white/50 transition-colors">Distances</a>
          </div>

          <p className="text-[12px] text-white/15">
            &copy; 2025 Stride. All rights reserved.
          </p>
        </div>
      </div>
    </footer>
  )
}
