const distances = [
  { num: '5K', name: 'Speed' },
  { num: '10K', name: 'Speed' },
  { num: '21K', name: 'Half Marathon' },
  { num: '42K', name: 'Marathon' },
  { num: '50K', name: 'Ultra' },
  { num: '80K', name: 'Ultra' },
  { num: '100K', name: 'Ultra' },
  { num: '160K', name: 'Ultra' },
  { num: '160+', name: 'Ultra' },
]

export default function Distances() {
  return (
    <section id="distances" className="py-24 md:py-36 bg-bg-light relative overflow-hidden">
      <div className="max-w-[1400px] mx-auto px-6">
        <div className="text-center mb-16">
          <p data-reveal className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
            Every Distance
          </p>
          <h2 data-reveal data-reveal-delay="1" className="font-inter font-bold text-[clamp(32px,5vw,56px)] leading-tight text-brand-black">
            5K to 160+ kilometres.<br className="hidden sm:block" /> We've got your race.
          </h2>
        </div>

        <div className="flex gap-2 justify-center flex-wrap">
          {distances.map((d, i) => (
            <div
              key={d.num}
              data-reveal
              data-reveal-delay={String(Math.min(i + 1, 8))}
              className="group w-[120px] py-8 px-3 bg-white border border-brand-black/[0.06] text-center relative overflow-hidden transition-all duration-300 hover:border-stride-red/30 hover:-translate-y-1.5 hover:shadow-[0_20px_50px_rgba(0,0,0,0.08)]"
            >
              {/* Bottom accent line */}
              <div className="absolute bottom-0 left-0 right-0 h-0.5 bg-stride-red scale-x-0 group-hover:scale-x-100 transition-transform duration-300 origin-left" />

              <div className="font-barlow font-bold text-[40px] text-brand-black leading-none mb-1.5">
                {d.num}
              </div>
              <div className="text-[13px] font-medium text-brand-black/30 uppercase tracking-[0.08em]">
                {d.name}
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
