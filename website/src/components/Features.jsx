const features = [
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" />
        <path d="M8 12l3 3 5-6" />
      </svg>
    ),
    title: 'AI Coaching Intelligence',
    desc: 'Three expert coaching personas analyze your fitness, detect conflicts between your goals and ability, and build plans that actually work.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
      </svg>
    ),
    title: 'Real-Time Plan Generation',
    desc: 'Watch your personalized training plan build live. Modify it anytime with natural language — just tell your coach what you need.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="5" cy="16" r="2.5" />
        <circle cx="19" cy="16" r="2.5" />
        <path d="M5 13.5C5.8 14 8.5 15 12 15M7 12c.5.5 2.5 1.5 5.5 1.5S18 12.5 17 12" />
        <path d="M17 12l2-8h-7c-1 0-1.5.5-1.5 1.5S11.5 7 12.5 7H16" />
      </svg>
    ),
    title: 'Assault Runner Integration',
    desc: 'Connect your Assault Runner via Bluetooth. Track every split, monitor pace in real time, and log actual performance against your plan.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 3v18h18" />
        <polyline points="7 16 11 8 15 13 19 5" />
      </svg>
    ),
    title: 'Structured Periodization',
    desc: 'BUILD. CONSOLIDATE. RECOVER. SHARPEN. Every training phase engineered for peak race-day performance.',
  },
]

export default function Features() {
  return (
    <section id="features" className="relative min-h-screen flex items-center overflow-hidden">
      {/* Full-bleed background image */}
      <div className="absolute inset-0">
        <img
          src="/photos/runner-sprint-dark.webp"
          alt=""
          className="absolute inset-0 w-full h-full object-cover"
        />
      </div>

      {/* Dark overlay for text readability */}
      <div className="absolute inset-0 bg-bg-dark/75" />

      <div className="relative z-10 max-w-[1400px] mx-auto px-6 py-24 md:py-36 w-full">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-24 items-start">
          {/* Left: text */}
          <div className="lg:sticky lg:top-40">
            <p
              data-reveal
              className="font-barlow font-semibold text-[13px] tracking-[0.3em] uppercase text-stride-red mb-4"
            >
              Built for Serious Runners
            </p>
            <h2
              data-reveal
              data-reveal-delay="1"
              className="font-inter font-bold text-[clamp(32px,4vw,52px)] leading-tight text-white mb-6"
            >
              Everything you need to crush your next race.
            </h2>
            <p
              data-reveal
              data-reveal-delay="2"
              className="text-base text-white/40 leading-relaxed max-w-md font-light"
            >
              Stride combines AI coaching intelligence with real-time treadmill
              integration to deliver training plans that adapt to you.
            </p>
          </div>

          {/* Right: feature cards */}
          <div className="grid grid-cols-1 gap-4">
            {features.map((f, i) => (
              <div
                key={f.title}
                data-reveal
                data-reveal-delay={String(i + 1)}
                className="group relative bg-bg-dark/60 backdrop-blur-sm border border-white/[0.08] p-8 transition-all duration-300 hover:border-stride-red/20 hover:-translate-y-1 hover:shadow-[0_20px_60px_rgba(0,0,0,0.3)]"
              >
                <div className="absolute top-0 left-0 w-12 h-[3px] bg-stride-red transition-all duration-500 group-hover:w-full" />

                <div className="flex items-start gap-5">
                  <div className="flex-shrink-0 w-10 h-10 bg-stride-red/10 flex items-center justify-center text-stride-red">
                    {f.icon}
                  </div>
                  <div>
                    <h3 className="font-inter font-semibold text-lg text-white mb-2">
                      {f.title}
                    </h3>
                    <p className="text-[15px] text-white/40 leading-relaxed font-light">
                      {f.desc}
                    </p>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
