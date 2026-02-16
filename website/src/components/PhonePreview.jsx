import StrideLogo from './StrideLogo'

export default function PhonePreview() {
  return (
    <section className="relative min-h-screen flex items-center overflow-hidden">
      {/* Full-bleed background image */}
      <div className="absolute inset-0">
        <img
          src="/photos/motion-track.jpg"
          alt=""
          className="absolute inset-0 w-full h-full object-cover"
        />
      </div>

      {/* Dark overlay */}
      <div className="absolute inset-0 bg-bg-dark/70" />

      <div className="relative z-10 max-w-[1400px] mx-auto px-6 py-24 md:py-36 w-full">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-24 items-center">
          {/* Text */}
          <div>
            <p data-reveal className="font-barlow font-semibold text-[13px] tracking-[0.3em] uppercase text-stride-red mb-4">
              Your Training Plan
            </p>
            <h2 data-reveal data-reveal-delay="1" className="font-inter font-bold text-[clamp(32px,4vw,48px)] leading-tight text-white mb-6">
              Week by week.<br />Workout by workout.
            </h2>
            <p data-reveal data-reveal-delay="2" className="text-base text-white/40 leading-relaxed mb-4 font-light">
              Every session is purpose-built — easy runs, tempo work, intervals, long runs, strength sessions. Each week has a training focus: BUILD progressive overload, CONSOLIDATE your gains, RECOVER with reduced volume, and SHARPEN for race day.
            </p>
            <p data-reveal data-reveal-delay="3" className="text-base text-white/40 leading-relaxed font-light">
              Navigate between weeks, track completions, and see exactly what's ahead. Your plan adapts to your preferred rest days, long run day, and training load.
            </p>
          </div>

          {/* Phone mockup */}
          <div data-reveal data-reveal-delay="2" className="flex justify-center" style={{ perspective: '1000px' }}>
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
    </section>
  )
}

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
