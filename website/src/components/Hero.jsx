export default function Hero() {
  return (
    <section id="hero" className="relative min-h-screen flex items-end pb-24 pt-40 overflow-hidden">
      {/* Background video */}
      <div className="absolute inset-0 bg-bg-dark">
        <video
          autoPlay
          muted
          loop
          playsInline
          className="absolute inset-0 w-full h-full object-cover"
        >
          <source src="/hero-video.mp4" type="video/mp4" />
        </video>
      </div>

      {/* Gradient overlay */}
      <div className="hero-video-overlay absolute inset-0 z-[1]" />

      {/* Content */}
      <div className="relative z-10 max-w-[1400px] mx-auto px-6 w-full">
        <div className="max-w-4xl">
          <div data-reveal>
            <p className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-6">
              AI Running Coach
            </p>
          </div>

          <h1
            data-reveal
            data-reveal-delay="1"
            className="font-inter font-black text-[clamp(48px,8vw,110px)] leading-[0.95] tracking-tight text-white mb-8"
          >
            Built<br />
            <span className="text-gradient-red">Different.</span>
          </h1>

          <p
            data-reveal
            data-reveal-delay="2"
            className="text-lg md:text-xl text-white/40 max-w-xl leading-relaxed mb-12 font-light"
          >
            Personalized training plans for every distance — 5K to ultra.
            Powered by elite coaching intelligence. Built for the Assault Runner.
          </p>

          <div data-reveal data-reveal-delay="3" className="flex items-center gap-6 flex-wrap">
            <a
              href="#download"
              className="inline-flex items-center gap-3 bg-stride-red text-white font-semibold text-lg px-10 py-4 rounded-[10px] hover:bg-stride-dark-red transition-all hover:-translate-y-0.5 hover:shadow-[0_12px_40px_rgba(255,38,23,0.3)]"
            >
              <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor">
                <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
              </svg>
              Get the App
            </a>
            <a
              href="#features"
              className="text-white/40 hover:text-white font-medium text-base transition-colors flex items-center gap-2"
            >
              Explore Features
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M7 13l5 5 5-5M7 6l5 5 5-5" />
              </svg>
            </a>
          </div>
        </div>
      </div>
    </section>
  )
}
