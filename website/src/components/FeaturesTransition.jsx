import { useRef, useEffect } from 'react'
import StrideLogo from './StrideLogo'

const features = [
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z" />
        <path d="M8 12l3 3 5-6" />
      </svg>
    ),
    title: 'AI Coaching Intelligence',
    desc: 'Three expert personas analyze your fitness, detect conflicts, and build plans that match your ability.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
      </svg>
    ),
    title: 'Real-Time Plan Generation',
    desc: 'Watch your training plan build live. Modify it anytime with natural language.',
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
    desc: 'Connect via Bluetooth. Track every split, monitor pace in real time.',
  },
  {
    icon: (
      <svg viewBox="0 0 24 24" className="w-5 h-5" strokeWidth="1.5" stroke="currentColor" fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M3 3v18h18" />
        <polyline points="7 16 11 8 15 13 19 5" />
      </svg>
    ),
    title: 'Structured Periodization',
    desc: 'BUILD. CONSOLIDATE. RECOVER. SHARPEN. Every phase engineered for peak performance.',
  },
]

function clamp(v) {
  return Math.max(0, Math.min(1, v))
}

export default function FeaturesTransition() {
  const wrapperRef = useRef(null)
  const bg1Ref = useRef(null)
  const bg2Ref = useRef(null)
  const s1Ref = useRef(null)
  const s2Ref = useRef(null)

  useEffect(() => {
    const wrapper = wrapperRef.current
    if (!wrapper) return
    const bg1 = bg1Ref.current
    const bg2 = bg2Ref.current
    const s1 = s1Ref.current
    const s2 = s2Ref.current

    const onScroll = () => {
      const rect = wrapper.getBoundingClientRect()
      const scrollable = wrapper.offsetHeight - window.innerHeight
      if (scrollable <= 0) return
      const p = clamp(-rect.top / scrollable)

      // Background crossfade (30% → 65%)
      const bg = clamp((p - 0.3) / 0.35)
      bg1.style.opacity = 1 - bg
      bg2.style.opacity = bg

      // Section 1 exits (0% → 40%)
      const a = 1 - clamp(p / 0.4)
      s1.style.opacity = a
      s1.style.transform = `translateY(${(1 - a) * -80}px)`
      s1.style.pointerEvents = a < 0.1 ? 'none' : ''

      // Section 2 enters (55% → 90%)
      const b = clamp((p - 0.55) / 0.35)
      s2.style.opacity = b
      s2.style.transform = `translateY(${(1 - b) * 80}px)`
      s2.style.pointerEvents = b < 0.1 ? 'none' : ''
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    onScroll()
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <div ref={wrapperRef} id="features" className="relative" style={{ height: '280vh' }}>
      <div className="sticky top-0 h-screen overflow-hidden">
        {/* Background layers */}
        <img
          ref={bg1Ref}
          src="/photos/assault-runner-sprint.jpg"
          alt=""
          className="absolute inset-0 w-full h-full object-cover"
        />
        <img
          ref={bg2Ref}
          src="/photos/motion-track.jpg"
          alt=""
          className="absolute inset-0 w-full h-full object-cover"
          style={{ opacity: 0 }}
        />
        <div className="absolute inset-0 bg-bg-dark/75" />

        {/* Section 1: Features */}
        <div ref={s1Ref} className="absolute inset-0 z-10 flex items-center will-change-transform">
          <div className="max-w-[1400px] mx-auto px-6 w-full">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 lg:gap-20 items-start">
              {/* Left text */}
              <div>
                <p className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
                  Built for Serious Runners
                </p>
                <h2 className="font-inter font-bold text-[clamp(28px,3.5vw,48px)] leading-tight text-white mb-6">
                  Everything you need to crush your next race.
                </h2>
                <p className="text-lg text-white/40 leading-relaxed max-w-md font-light">
                  Stride combines AI coaching intelligence with real-time treadmill
                  integration to deliver training plans that adapt to you.
                </p>
              </div>

              {/* Right: 2×2 feature cards */}
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                {features.map((f) => (
                  <div
                    key={f.title}
                    className="group relative bg-bg-dark/60 backdrop-blur-sm border border-white/[0.08] p-5 transition-all duration-300 hover:border-stride-red/20"
                  >
                    <div className="absolute top-0 left-0 w-8 h-[2px] bg-stride-red transition-all duration-500 group-hover:w-full" />
                    <div className="flex items-start gap-3">
                      <div className="flex-shrink-0 w-8 h-8 bg-stride-red/10 flex items-center justify-center text-stride-red">
                        {f.icon}
                      </div>
                      <div>
                        <h3 className="font-inter font-semibold text-base text-white mb-1">
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
        </div>

        {/* Section 2: Training Plan + Phone */}
        <div ref={s2Ref} className="absolute inset-0 z-10 flex items-center will-change-transform" style={{ opacity: 0 }}>
          <div className="max-w-[1400px] mx-auto px-6 w-full">
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-24 items-center">
              {/* Left text */}
              <div>
                <p className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
                  Your Training Plan
                </p>
                <h2 className="font-inter font-bold text-[clamp(28px,3.5vw,48px)] leading-tight text-white mb-6">
                  Week by week.<br />Workout by workout.
                </h2>
                <p className="text-lg text-white/40 leading-relaxed mb-4 font-light">
                  Every session is purpose-built — easy runs, tempo work, intervals, long runs, strength sessions. Each week has a training focus: BUILD progressive overload, CONSOLIDATE your gains, RECOVER with reduced volume, and SHARPEN for race day.
                </p>
                <p className="text-lg text-white/40 leading-relaxed font-light">
                  Navigate between weeks, track completions, and see exactly what's ahead.
                </p>
              </div>

              {/* Right: phone mockup */}
              <div className="flex justify-center" style={{ perspective: '1000px' }}>
                <div className="animate-float">
                  <div className="iphone-frame">
                    <div className="iphone-notch" />
                    <div className="iphone-screen">
                      <PlanScreen />
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

/* ── Phone screen content ── */

function PlanScreen() {
  const workouts = [
    { day: 'Mon', num: 10, type: 'Easy Run', name: 'Recovery Run', detail: '6.0 km · 6:10/km', color: '#34C759', done: true },
    { day: 'Tue', num: 11, type: 'Intervals', name: '6 × 800m', detail: '9.0 km · 4:20/km reps', color: '#FF2617', done: true },
    { day: 'Wed', num: 12, type: 'Rest Day', name: 'Recovery', detail: '', color: '#BF5AF2', done: false },
    { day: 'Thu', num: 13, type: 'Tempo', name: 'Threshold Run', detail: '10.0 km · 4:50/km', color: '#FF9500', done: false },
    { day: 'Fri', num: 14, type: 'Gym', name: 'Strength Session', detail: '45 min', color: '#FFD60A', done: false },
    { day: 'Sat', num: 15, type: 'Long Run', name: 'Aerobic Endurance', detail: '18.0 km · 5:40/km', color: '#FFD60A', done: false },
  ]

  return (
    <div className="p-3 pt-9 h-full flex flex-col font-inter text-white">
      <div className="flex justify-center py-2">
        <StrideLogo className="h-[18px] w-auto" />
      </div>

      <div className="flex gap-1.5 py-3 overflow-hidden">
        {['W1', 'W2', 'W3', 'W4', 'W5', 'W6', 'W7'].map((w, i) => (
          <div
            key={w}
            className={`w-[34px] h-[44px] flex items-center justify-center rounded-full text-[11px] font-semibold shrink-0 ${
              i === 2 ? 'bg-stride-red text-white' : 'bg-[#2A2A2E] text-white/40'
            }`}
          >
            {w}
          </div>
        ))}
      </div>

      <div className="flex-1 overflow-hidden flex flex-col gap-1.5">
        {workouts.map((w) => (
          <div key={w.day} className="flex items-center gap-2.5 bg-[#1C1C1E] rounded-[10px] p-2.5">
            <div className="text-center min-w-[34px]">
              <div className="text-[9px] text-white/35 uppercase">{w.day}</div>
              <div className="font-barlow text-lg font-semibold">{w.num}</div>
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-[9px] font-semibold uppercase tracking-wide" style={{ color: w.color }}>
                {w.type}
              </div>
              <div className="text-[13px] font-medium truncate">{w.name}</div>
              {w.detail && <div className="text-[10px] text-white/35">{w.detail}</div>}
            </div>
            <div className={`w-[18px] h-[18px] rounded-full shrink-0 flex items-center justify-center ${
              w.done ? 'bg-stride-red' : 'bg-[#2A2A2E]'
            }`}>
              {w.done && (
                <svg viewBox="0 0 10 10" className="w-[10px] h-[10px]" fill="none" stroke="white" strokeWidth="1.5">
                  <polyline points="2 5 4.5 7.5 8 3" />
                </svg>
              )}
            </div>
          </div>
        ))}
      </div>

      <TabBar active="plan" />
    </div>
  )
}

function TabBar({ active }) {
  const tabs = [
    { id: 'run', label: 'Run', icon: <path d="M12 2a4 4 0 014 4c0 2-2 4-4 6-2-2-4-4-4-6a4 4 0 014-4z M12 12v8" /> },
    { id: 'plan', label: 'Plan', icon: <><path d="M12.9 17.9L19.3 1H10.4L6.6 11.9" /><path d="M10.4 1L6.6 11.9H1.4L4.6 3.2H9.4" /></> },
    { id: 'stats', label: 'Stats', icon: <><path d="M3 3v18h18" /><polyline points="7 16 11 8 15 13 19 5" /></> },
    { id: 'settings', label: 'Settings', icon: <><circle cx="12" cy="12" r="3" /><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42" /></> },
  ]

  return (
    <div className="flex justify-center py-2">
      <div className="flex gap-6 bg-[#1E1E20]/95 backdrop-blur-sm rounded-3xl px-6 py-2 shadow-[0_4px_20px_rgba(255,38,23,0.08)]">
        {tabs.map(t => {
          const isActive = t.id === active
          return (
            <div key={t.id} className="text-center">
              <svg
                viewBox={t.id === 'plan' ? '0 0 21 19' : '0 0 24 24'}
                className="w-[18px] h-[18px] mb-0.5"
                strokeWidth="2"
                fill="none"
                stroke={isActive ? '#FF2617' : 'rgba(255,255,255,0.3)'}
              >
                {t.icon}
              </svg>
              <div className={`text-[8px] ${isActive ? 'text-stride-red' : 'text-white/30'}`}>
                {t.label}
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
