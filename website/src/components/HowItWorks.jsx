const steps = [
  {
    num: '01',
    title: 'Set Your Goal',
    desc: 'Pick your distance, set your race date, tell us your target time.',
  },
  {
    num: '02',
    title: 'Get Your Plan',
    desc: 'AI analyzes your fitness and builds a week-by-week plan in real time.',
  },
  {
    num: '03',
    title: 'Train Smart',
    desc: 'Follow structured workouts with 8 precise pace zones. Edit anytime in plain English.',
  },
  {
    num: '04',
    title: 'Crush It',
    desc: 'Track every session. Get AI performance analysis. Arrive at the start line ready.',
  },
]

export default function HowItWorks() {
  return (
    <section id="how-it-works" className="py-24 md:py-36 bg-bg-dark relative overflow-hidden">
      {/* Borders */}
      <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/[0.06] to-transparent" />
      <div className="absolute bottom-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/[0.06] to-transparent" />

      <div className="max-w-[1400px] mx-auto px-6">
        <div className="text-center mb-20">
          <p data-reveal className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
            How It Works
          </p>
          <h2 data-reveal data-reveal-delay="1" className="font-inter font-bold text-[clamp(32px,5vw,56px)] leading-tight text-white">
            From goal to finish line<br className="hidden sm:block" /> in four steps.
          </h2>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-4 gap-12 md:gap-6">
          {steps.map((step, i) => (
            <div key={step.num} data-reveal data-reveal-delay={String(i + 1)} className="relative text-center">
              {/* Large number */}
              <div className="font-barlow font-bold text-[clamp(64px,10vw,100px)] leading-none text-gradient-red mb-4 opacity-80">
                {step.num}
              </div>

              <h3 className="font-inter font-semibold text-lg uppercase tracking-[0.08em] text-white mb-3">
                {step.title}
              </h3>

              <p className="text-base text-white/35 leading-relaxed max-w-[240px] mx-auto font-light">
                {step.desc}
              </p>

              {/* Connecting line (desktop only) */}
              {i < steps.length - 1 && (
                <div className="hidden md:block absolute top-12 right-0 w-[calc(100%-80px)] h-px bg-gradient-to-r from-white/[0.08] to-transparent translate-x-full" />
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
