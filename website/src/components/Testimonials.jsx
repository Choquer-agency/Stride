import { useEffect, useRef, useState } from 'react'

const testimonials = [
  {
    quote: "Stride completely changed how I approach my marathon training. The AI coach detected I was overtraining and adjusted my plan before I burned out.",
    name: "Sarah K.",
    detail: "Marathon · 3:28 PR",
    avatar: "SK",
  },
  {
    quote: "I went from a 52-minute 10K to a 46-minute PB in 12 weeks. The structured periodization and pace zones are next level.",
    name: "James T.",
    detail: "10K · 46:12 PR",
    avatar: "JT",
  },
  {
    quote: "The Assault Runner integration is seamless. Live pace tracking during workouts makes every interval session so much more effective.",
    name: "Maria L.",
    detail: "Half Marathon · 1:39 PR",
    avatar: "ML",
  },
  {
    quote: "Being able to edit my plan with natural language is incredible. I just told it to add more hill work and it restructured everything intelligently.",
    name: "David P.",
    detail: "Ultra 50K · First finish",
    avatar: "DP",
  },
  {
    quote: "As a coach myself, I'm impressed by the periodization quality. Build, consolidate, recover, sharpen — it nails the progression every time.",
    name: "Coach Mike R.",
    detail: "Running Coach · 15 years",
    avatar: "MR",
  },
  {
    quote: "I never thought I'd run an ultra. Stride took me from half marathons to a 50K in 6 months with zero injuries. The recovery planning is perfect.",
    name: "Priya N.",
    detail: "Ultra 50K · 5:12",
    avatar: "PN",
  },
]

export default function Testimonials() {
  const trackRef = useRef(null)
  const [isPaused, setIsPaused] = useState(false)

  useEffect(() => {
    const track = trackRef.current
    if (!track) return

    let animationId
    let position = 0
    const speed = 0.5

    function animate() {
      if (!isPaused) {
        position -= speed
        const halfWidth = track.scrollWidth / 2
        if (Math.abs(position) >= halfWidth) {
          position = 0
        }
        track.style.transform = `translateX(${position}px)`
      }
      animationId = requestAnimationFrame(animate)
    }

    animationId = requestAnimationFrame(animate)
    return () => cancelAnimationFrame(animationId)
  }, [isPaused])

  const allTestimonials = [...testimonials, ...testimonials]

  return (
    <section className="py-24 md:py-36 bg-bg-light relative overflow-hidden">
      <div className="max-w-[1400px] mx-auto px-6 mb-16">
        <p data-reveal className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
          What Runners Say
        </p>
        <h2 data-reveal data-reveal-delay="1" className="font-inter font-bold text-[clamp(32px,5vw,56px)] leading-tight text-brand-black">
          Trusted by runners<br className="hidden sm:block" /> at every level.
        </h2>
      </div>

      {/* Sliding track */}
      <div
        className="relative"
        onMouseEnter={() => setIsPaused(true)}
        onMouseLeave={() => setIsPaused(false)}
      >
        {/* Fade edges */}
        <div className="absolute left-0 top-0 bottom-0 w-24 bg-gradient-to-r from-bg-light to-transparent z-10 pointer-events-none" />
        <div className="absolute right-0 top-0 bottom-0 w-24 bg-gradient-to-l from-bg-light to-transparent z-10 pointer-events-none" />

        <div ref={trackRef} className="flex gap-5 will-change-transform" data-reveal>
          {allTestimonials.map((t, i) => (
            <div
              key={i}
              className="flex-shrink-0 w-[380px] bg-white border border-brand-black/[0.06] p-8 flex flex-col transition-all duration-300 hover:border-stride-red/20 hover:shadow-[0_8px_30px_rgba(0,0,0,0.06)]"
            >
              {/* Stars */}
              <div className="flex gap-1 mb-5">
                {[...Array(5)].map((_, j) => (
                  <svg key={j} width="14" height="14" viewBox="0 0 24 24" fill="#FF2617">
                    <path d="M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01L12 2z" />
                  </svg>
                ))}
              </div>

              {/* Quote */}
              <p className="text-lg text-brand-black/50 leading-relaxed font-light flex-1 mb-6">
                &ldquo;{t.quote}&rdquo;
              </p>

              {/* Author */}
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-stride-red/10 flex items-center justify-center text-stride-red text-[13px] font-bold font-barlow rounded-full">
                  {t.avatar}
                </div>
                <div>
                  <p className="text-base font-semibold text-brand-black">{t.name}</p>
                  <p className="text-[12px] text-brand-black/30">{t.detail}</p>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
