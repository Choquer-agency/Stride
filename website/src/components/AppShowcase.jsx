import StrideLogo from './StrideLogo'

export default function AppShowcase() {
  return (
    <section className="h-screen bg-bg-light overflow-hidden flex flex-col justify-center">
      <div className="max-w-[1400px] mx-auto px-6 w-full">
        {/* Header */}
        <div className="text-center mb-6 md:mb-10" data-reveal>
          <p className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-3">
            The App
          </p>
          <h2 className="font-inter font-bold text-[clamp(24px,3.5vw,44px)] leading-tight text-brand-black">
            Your entire training ecosystem.
          </h2>
        </div>

        {/* 3-column coded screens */}
        <div className="flex justify-center gap-2 md:gap-3 max-h-[68vh]">
          <div data-reveal data-reveal-delay="1" className="flex flex-col items-center">
            <div className="w-[28vw] max-w-[280px] h-full overflow-hidden rounded-[10px] shadow-[0_8px_40px_rgba(0,0,0,0.1)] border border-black/[0.04]">
              <GoalScreen />
            </div>
            <div className="mt-3 text-center shrink-0 w-[80%]">
              <p className="font-barlow font-semibold text-[14px] tracking-[0.15em] uppercase text-brand-black/40 mb-0.5">Set Your Goal</p>
              <p className="text-sm text-brand-black/30 font-light hidden md:block">Choose your distance, race date, and target time.</p>
            </div>
          </div>

          <div data-reveal data-reveal-delay="2" className="flex flex-col items-center">
            <div className="w-[28vw] max-w-[280px] h-full overflow-hidden rounded-[10px] shadow-[0_8px_40px_rgba(0,0,0,0.1)] border border-black/[0.04]">
              <WeeklyPlanScreen />
            </div>
            <div className="mt-3 text-center shrink-0 w-[80%]">
              <p className="font-barlow font-semibold text-[14px] tracking-[0.15em] uppercase text-brand-black/40 mb-0.5">Weekly Plan</p>
              <p className="text-sm text-brand-black/30 font-light hidden md:block">Structured workouts that adapt to your schedule.</p>
            </div>
          </div>

          <div data-reveal data-reveal-delay="3" className="flex flex-col items-center">
            <div className="w-[28vw] max-w-[280px] h-full overflow-hidden rounded-[10px] shadow-[0_8px_40px_rgba(0,0,0,0.1)] border border-black/[0.04]">
              <RunScreen />
            </div>
            <div className="mt-3 text-center shrink-0 w-[80%]">
              <p className="font-barlow font-semibold text-[14px] tracking-[0.15em] uppercase text-brand-black/40 mb-0.5">Active Run</p>
              <p className="text-sm text-brand-black/30 font-light hidden md:block">Real-time pace and splits from your Assault Runner.</p>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

/* ── Helpers ── */

function formatDate(d) {
  return d.toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' })
}

function getWeekDates() {
  const now = new Date()
  const day = now.getDay()
  const monday = new Date(now)
  monday.setDate(now.getDate() - ((day + 6) % 7))
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday)
    d.setDate(monday.getDate() + i)
    return d
  })
}

function isBeforeToday(d) {
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const check = new Date(d)
  check.setHours(0, 0, 0, 0)
  return check < today
}

function isToday(d) {
  const today = new Date()
  return d.getDate() === today.getDate() && d.getMonth() === today.getMonth() && d.getFullYear() === today.getFullYear()
}

/* ══════════════════════════════════════════
   SCREEN 1: Goal Setting
   ══════════════════════════════════════════ */

function GoalScreen() {
  const raceDate = new Date()
  raceDate.setDate(raceDate.getDate() + 87)

  return (
    <div className="bg-white h-full flex flex-col font-inter text-[#1C1C1E]" style={{ fontSize: '11px' }}>
      {/* Status bar spacer */}
      <div className="h-6 shrink-0" />

      {/* Stride logo */}
      <div className="flex justify-center py-2 shrink-0">
        <StrideLogo className="h-[16px] w-auto" color="#FF2617" />
      </div>

      {/* Step indicators */}
      <div className="flex justify-center gap-6 py-3 shrink-0">
        {[
          { n: 1, label: 'Goal', active: true },
          { n: 2, label: 'Fitness', active: false },
          { n: 3, label: 'Schedule', active: false },
          { n: 4, label: 'History', active: false },
        ].map(s => (
          <div key={s.n} className="flex flex-col items-center gap-1">
            <div className={`w-[22px] h-[22px] rounded-full flex items-center justify-center text-[9px] font-bold ${
              s.active ? 'bg-stride-red text-white' : 'bg-[#F2F2F7] text-[#8E8E93]'
            }`}>
              {s.n}
            </div>
            <span className={`text-[8px] font-medium ${s.active ? 'text-stride-red' : 'text-[#8E8E93]'}`}>
              {s.label}
            </span>
          </div>
        ))}
      </div>

      {/* Form content */}
      <div className="flex-1 overflow-hidden px-4 pt-3">
        {/* Title */}
        <h3 className="font-barlow font-bold text-[18px] tracking-tight leading-tight mb-1">
          WHAT'S YOUR GOAL?
        </h3>
        <p className="text-[10px] text-[#8E8E93] mb-4 leading-snug">
          Tell us about the race you're training for — or the outcome you want to achieve.
        </p>

        <div className="flex flex-col gap-3">
          {/* Race Distance */}
          <FormField label="Race Distance">
            <div className="flex items-center justify-between px-3 py-2.5 bg-[#F2F2F7] rounded-[8px]">
              <span className="text-[11px]">Marathon</span>
              <ChevronDown />
            </div>
          </FormField>

          {/* Race Date */}
          <FormField label="Race Date">
            <div className="flex items-center justify-between px-3 py-2.5 bg-[#F2F2F7] rounded-[8px]">
              <span className="text-[11px]">{formatDate(raceDate)}</span>
              <CalendarIcon />
            </div>
          </FormField>

          {/* Race Name */}
          <FormField label="Race Name">
            <div className="px-3 py-2.5 bg-[#F2F2F7] rounded-[8px]">
              <span className="text-[11px] text-[#C7C7CC]">e.g. Boston Marathon</span>
            </div>
          </FormField>

          {/* Goal Time */}
          <FormField label="Goal Time">
            <div className="px-3 py-2.5 bg-[#F2F2F7] rounded-[8px]">
              <span className="text-[11px] text-[#C7C7CC]">e.g. 3:30:00</span>
            </div>
          </FormField>
        </div>
      </div>
    </div>
  )
}

function FormField({ label, children }) {
  return (
    <div>
      <div className="flex items-center gap-0.5 mb-1">
        <span className="text-[10px] font-medium text-[#1C1C1E]">{label}</span>
        <span className="text-[10px] text-stride-red">*</span>
      </div>
      {children}
    </div>
  )
}

function ChevronDown() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#FF2617" strokeWidth="2.5" strokeLinecap="round">
      <path d="M6 9l6 6 6-6" />
    </svg>
  )
}

function CalendarIcon() {
  return (
    <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#FF2617" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      <rect x="3" y="4" width="18" height="18" rx="2" />
      <path d="M16 2v4M8 2v4M3 10h18" />
    </svg>
  )
}

/* ══════════════════════════════════════════
   SCREEN 2: Weekly Plan (live dates!)
   ══════════════════════════════════════════ */

function WeeklyPlanScreen() {
  const weekDates = getWeekDates()
  const todayDate = new Date()
  const daysUntilRace = 87

  const workoutPlan = [
    { type: 'rest', title: 'Rest Day', color: '#8A0063', isRest: true },
    { type: 'easy', title: 'Easy Run', detail: '8 km · 5:40/km', color: '#34C759' },
    { type: 'intervals', title: '6 × 800m', detail: '9 km · 4:20/km', color: '#FF2617' },
    { type: 'easy', title: 'Easy Run', detail: '6 km · 5:50/km', color: '#34C759' },
    { type: 'tempo', title: 'Tempo Run', detail: '10 km · 4:50/km', color: '#FF9500' },
    { type: 'gym', title: 'Strength', detail: '45 min', color: '#CF0000' },
    { type: 'long', title: 'Long Run', detail: '18 km · 5:30/km', color: '#007AFF' },
  ]

  const days = weekDates.map((date, i) => ({
    date,
    ...workoutPlan[i],
    done: isBeforeToday(date),
    isToday: isToday(date),
  }))

  const completedCount = days.filter(d => d.done).length

  return (
    <div className="bg-white h-full flex flex-col font-inter text-[#1C1C1E]" style={{ fontSize: '11px' }}>
      {/* Status bar spacer */}
      <div className="h-6 shrink-0" />

      {/* Stride logo */}
      <div className="flex justify-center py-2 shrink-0">
        <StrideLogo className="h-[16px] w-auto" color="#FF2617" />
      </div>

      {/* Stats row */}
      <div className="flex justify-center gap-6 px-4 py-2 shrink-0">
        <div className="flex items-center gap-1.5">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#1C1C1E" strokeWidth="2" strokeLinecap="round">
            <circle cx="12" cy="12" r="10" />
            <path d="M12 6v6l4 2" />
          </svg>
          <span className="text-[10px] font-medium">{daysUntilRace} Days Until Race</span>
        </div>
        <div className="flex items-center gap-1.5">
          <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="#1C1C1E" strokeWidth="2" strokeLinecap="round">
            <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z" />
            <line x1="4" y1="22" x2="4" y2="15" />
          </svg>
          <span className="text-[10px] font-medium">{completedCount}/47 Completed</span>
        </div>
      </div>

      {/* Week pills */}
      <div className="flex gap-2 px-4 py-2 overflow-hidden shrink-0">
        {Array.from({ length: 8 }, (_, i) => (
          <div
            key={i}
            className={`w-[30px] h-[38px] flex items-center justify-center rounded-full text-[9px] font-semibold shrink-0 ${
              i === 2 ? 'bg-stride-red text-white' : 'bg-[#F2F2F7] text-[#8E8E93]'
            }`}
          >
            W{i + 1}
          </div>
        ))}
      </div>

      {/* Day cards */}
      <div className="flex-1 overflow-hidden px-3 pt-1 flex flex-col gap-1.5">
        {days.map((d) => (
          <DayCard key={d.date.toISOString()} day={d} />
        ))}
      </div>
    </div>
  )
}

function DayCard({ day }) {
  const shortDay = day.date.toLocaleDateString('en-US', { weekday: 'short' })
  const dayNum = day.date.getDate()
  const shortMonth = day.date.toLocaleDateString('en-US', { month: 'short' })

  if (day.isRest) {
    return (
      <div className="flex items-center gap-2 px-2.5 py-2 rounded-[8px]" style={{ backgroundColor: '#FFF6F6' }}>
        {/* Date */}
        <DateCol day={shortDay} num={dayNum} month={shortMonth} highlight={day.isToday} />
        {/* Heart icon */}
        <div className="w-[26px] h-[26px] rounded-full flex items-center justify-center" style={{ backgroundColor: 'rgba(138,0,99,0.12)' }}>
          <svg width="10" height="10" viewBox="0 0 24 24" fill="#8A0063" stroke="none">
            <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
          </svg>
        </div>
        <span className="text-[11px] font-medium">Rest Day</span>
      </div>
    )
  }

  return (
    <div className={`flex items-center gap-2 px-2.5 py-2 rounded-[8px] ${day.done ? 'opacity-50' : ''}`} style={{ backgroundColor: '#F9F9F9' }}>
      {/* Date */}
      <DateCol day={shortDay} num={dayNum} month={shortMonth} highlight={day.isToday} />
      {/* Type icon */}
      <WorkoutIcon type={day.type} color={day.color} />
      {/* Info */}
      <div className="flex-1 min-w-0 flex items-center gap-1.5">
        <span className="text-[11px] font-medium truncate">{day.title}</span>
        {day.detail && <span className="text-[9px] text-[#8E8E93] truncate hidden min-[400px]:inline">{day.detail}</span>}
      </div>
      {/* Status */}
      {day.done ? (
        <div className="w-[16px] h-[16px] rounded-full bg-stride-red flex items-center justify-center shrink-0">
          <svg width="8" height="8" viewBox="0 0 10 10" fill="none" stroke="white" strokeWidth="1.5">
            <polyline points="2 5 4.5 7.5 8 3" />
          </svg>
        </div>
      ) : (
        <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="#FF2617" strokeWidth="3" strokeLinecap="round" className="shrink-0">
          <path d="M9 18l6-6-6-6" />
        </svg>
      )}
    </div>
  )
}

function DateCol({ day, num, month, highlight }) {
  return (
    <div className={`flex flex-col items-center w-[30px] shrink-0 ${highlight ? 'text-stride-red' : ''}`}>
      <span className={`text-[7px] font-semibold uppercase ${highlight ? 'text-stride-red' : 'text-[#8E8E93]'}`}>{day}</span>
      <span className={`font-barlow text-[16px] font-semibold leading-none ${highlight ? 'text-stride-red' : 'text-[#1C1C1E]'}`}>{num}</span>
      <span className={`text-[7px] font-semibold uppercase ${highlight ? 'text-stride-red' : 'text-[#8E8E93]'}`}>{month}</span>
    </div>
  )
}

function WorkoutIcon({ type, color }) {
  const icons = {
    easy: <path d="M13 5.5C13 3.57 11.43 2 9.5 2S6 3.57 6 5.5 7.57 9 9.5 9 13 7.43 13 5.5zM9.5 11c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z" />,
    intervals: <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />,
    tempo: <><path d="M3 3v18h18" /><polyline points="7 16 11 8 15 13 19 5" /></>,
    gym: <path d="M6.5 6.5h11M4 10h16M6.5 17.5h11M2 14h4v-4H2v4zm16 0h4v-4h-4v4zM8 18h8V6H8v12z" />,
    long: <path d="M18 8h2a1 1 0 011 1v6a1 1 0 01-1 1h-2M6 8H4a1 1 0 00-1 1v6a1 1 0 001 1h2M22 12H2M12 2v4M12 18v4" />,
  }
  return (
    <div className="w-[26px] h-[26px] rounded-full flex items-center justify-center shrink-0" style={{ backgroundColor: color + '20' }}>
      <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
        {icons[type]}
      </svg>
    </div>
  )
}

/* ══════════════════════════════════════════
   SCREEN 3: Active Run
   ══════════════════════════════════════════ */

function RunScreen() {
  const splits = [
    { km: 1, pace: '5:12', time: '5:12', fastest: true },
    { km: 2, pace: '5:24', time: '10:36', fastest: false },
    { km: 3, pace: '5:31', time: '16:07', fastest: false },
    { km: 4, pace: '5:28', time: '21:35', fastest: false },
  ]

  // Pace graph data points (inverted — lower is faster)
  const graphPoints = [78, 72, 65, 70, 68, 75, 71, 66, 63, 69, 74, 70, 67, 65, 72, 76, 70, 68, 64, 71]

  return (
    <div className="bg-white h-full flex flex-col font-inter text-[#1C1C1E]" style={{ fontSize: '11px' }}>
      {/* Status bar spacer */}
      <div className="h-6 shrink-0" />

      {/* Header: Time | Logo | Distance */}
      <div className="flex items-start justify-between px-4 pt-1 pb-3 shrink-0">
        <div className="text-center">
          <div className="font-barlow text-[20px] font-medium leading-none">00:21:35</div>
          <div className="text-[8px] text-[#8E8E93] mt-0.5">Time</div>
        </div>
        <StrideLogo className="h-[16px] w-auto mt-1" color="#FF2617" />
        <div className="text-center">
          <div className="font-barlow text-[20px] font-medium leading-none">4.82</div>
          <div className="text-[8px] text-[#8E8E93] mt-0.5">Distance (km)</div>
        </div>
      </div>

      {/* Big pace */}
      <div className="text-center shrink-0 -my-1">
        <div className="font-barlow text-[72px] font-medium leading-[0.85] tracking-tight">5:28</div>
        <div className="text-[9px] text-[#8E8E93] mt-1">Pace (/km)</div>
      </div>

      {/* Pace graph */}
      <div className="px-4 py-3 shrink-0">
        <svg viewBox="0 0 200 40" className="w-full h-[32px]" preserveAspectRatio="none">
          {/* Grid lines */}
          {[0, 1, 2, 3].map(i => (
            <line key={i} x1="0" y1={i * 13} x2="200" y2={i * 13} stroke="#F2F2F7" strokeWidth="0.5" />
          ))}
          {/* Pace line */}
          <polyline
            fill="none"
            stroke="#FF2617"
            strokeWidth="1.5"
            strokeLinecap="round"
            strokeLinejoin="round"
            points={graphPoints.map((y, i) => `${(i / (graphPoints.length - 1)) * 200},${(y / 100) * 40}`).join(' ')}
          />
          {/* Current point */}
          <circle cx="200" cy={(graphPoints[graphPoints.length - 1] / 100) * 40} r="3" fill="#FF2617" />
        </svg>
      </div>

      {/* Metrics row */}
      <div className="flex justify-between px-4 pb-3 shrink-0">
        <div className="text-center">
          <div className="text-[8px] text-[#8E8E93]">Pace Drift</div>
          <div className="font-barlow text-[18px] font-medium leading-none mt-0.5">+1.2s</div>
        </div>
        <div className="text-center">
          <div className="text-[8px] text-[#8E8E93]">Heart Rate / Zone</div>
          <div className="font-barlow text-[18px] font-medium leading-none mt-0.5">147</div>
          <div className="text-[8px] font-medium mt-0.5" style={{ color: 'rgb(255,128,0)' }}>Z4 - Threshold</div>
        </div>
      </div>

      {/* Splits table */}
      <div className="flex-1 overflow-hidden px-4">
        {/* Header */}
        <div className="flex items-center text-[8px] text-[#8E8E93] font-medium pb-1.5 border-b border-[#F2F2F7]">
          <span className="w-[24px]">KM</span>
          <span className="w-[28px]" />
          <span className="flex-1 text-center">Pace</span>
          <span className="text-right w-[40px]">Time</span>
        </div>
        {/* Rows */}
        {splits.map((s, i) => (
          <div key={s.km} className={`flex items-center py-1.5 ${i < splits.length - 1 ? 'border-b border-stride-red/20' : ''}`}>
            <span className="font-barlow text-[14px] font-medium w-[24px]">{s.km}</span>
            <span className="w-[28px] flex items-center justify-center">
              {s.fastest && <span className="text-[10px]">🔥</span>}
            </span>
            <span className="font-barlow text-[14px] font-medium flex-1 text-center">{s.pace} /km</span>
            <span className="font-barlow text-[14px] font-medium text-right w-[40px]">{s.time}</span>
          </div>
        ))}
      </div>

      {/* Buttons */}
      <div className="flex gap-2 px-3 pb-4 pt-2 shrink-0">
        <div className="flex-1 py-2.5 bg-stride-red text-white text-[10px] font-semibold text-center rounded-[8px]">
          Pause Run
        </div>
        <div className="flex-1 py-2.5 bg-[#1C1C1E] text-white text-[10px] font-semibold text-center rounded-[8px]">
          End Run
        </div>
      </div>
    </div>
  )
}
