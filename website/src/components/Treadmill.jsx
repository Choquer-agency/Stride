import StrideLogo from './StrideLogo'

export default function Treadmill() {
  return (
    <section className="py-24 md:py-36 bg-bg-dark relative overflow-hidden">
      <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/[0.06] to-transparent" />

      <div className="max-w-[1400px] mx-auto px-6">
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 lg:gap-24 items-center">
          {/* Phone first on desktop (order swap) */}
          <div data-reveal data-reveal-delay="1" className="flex justify-center order-2 lg:order-1" style={{ perspective: '1000px' }}>
            <div className="animate-float" style={{ animationDelay: '-2s' }}>
              <div className="iphone-frame">
                <div className="iphone-notch" />
                <div className="iphone-screen">
                  <StatsScreen />
                </div>
              </div>
            </div>
          </div>

          {/* Text */}
          <div className="order-1 lg:order-2">
            <p data-reveal className="font-barlow font-semibold text-[16px] tracking-[0.3em] uppercase text-stride-red mb-4">
              Track Everything
            </p>
            <h2 data-reveal data-reveal-delay="1" className="font-inter font-bold text-[clamp(32px,4vw,48px)] leading-tight text-white mb-6">
              Your stats.<br />Your progress.
            </h2>
            <p data-reveal data-reveal-delay="2" className="text-lg text-white/40 leading-relaxed mb-4 font-light">
              See weekly distance, year-to-date totals, training composition, and long run progression — all in one place. Connect your Assault Runner for live Bluetooth pace tracking.
            </p>
            <p data-reveal data-reveal-delay="3" className="text-lg text-white/40 leading-relaxed mb-8 font-light">
              After each run, compare actual vs planned performance. Get AI analysis of your pacing, adherence, and areas to improve.
            </p>

            {/* Metrics */}
            <div data-reveal data-reveal-delay="4" className="flex gap-10 flex-wrap">
              <Metric label="Weekly KM" value="47.2" unit="km" />
              <Metric label="Avg Pace" value="5:28" unit="/km" />
              <Metric label="Longest Run" value="21.1" unit="km" />
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}

function Metric({ label, value, unit }) {
  return (
    <div>
      <div className="font-barlow text-[13px] tracking-[0.15em] uppercase text-white/30 mb-1">{label}</div>
      <div className="font-barlow font-bold text-4xl text-white leading-none">
        {value} <span className="text-base font-medium text-white/30">{unit}</span>
      </div>
    </div>
  )
}

function StatsScreen() {
  const statsData = [32, 38, 28, 42, 45, 35, 48, 40, 52, 47, 55, 42]

  return (
    <div className="p-3 pt-9 h-full flex flex-col font-inter text-white">
      <div className="flex justify-center py-2">
        <StrideLogo className="h-[18px] w-auto" />
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-1.5 mb-4">
        <StatCard label="This Week" value="47.2" sub="kilometres" change="+12%" />
        <StatCard label="Year to Date" value="842" sub="kilometres" />
        <StatCard label="4-Week Avg" value="43.6" sub="km / week" />
        <StatCard label="Race Day" value="47" sub="days to go" />
      </div>

      {/* Chart */}
      <div className="bg-[#1C1C1E] rounded-xl p-3 flex-1">
        <div className="flex justify-between items-center mb-3">
          <span className="text-[13px] font-semibold">Distance Over Time</span>
          <span className="text-[9px] text-stride-red font-medium">Weekly</span>
        </div>
        <div className="flex items-end gap-1 h-[100px]">
          {statsData.map((h, i) => (
            <div
              key={i}
              className={`flex-1 rounded-t animate-bar-grow ${
                i === statsData.length - 1 ? 'bg-stride-red' : 'bg-stride-red/30'
              }`}
              style={{
                height: `${(h / 55) * 100}%`,
                animationDelay: `${i * 0.06}s`,
              }}
            />
          ))}
        </div>
      </div>

      {/* Tab bar */}
      <div className="flex justify-center py-2">
        <div className="flex gap-6 bg-[#1E1E20]/95 backdrop-blur-sm rounded-3xl px-6 py-2 shadow-[0_4px_20px_rgba(255,38,23,0.08)]">
          {['Run', 'Plan', 'Stats', 'Settings'].map(t => (
            <div key={t} className="text-center">
              <div className={`w-[18px] h-[18px] mx-auto mb-0.5 rounded ${t === 'Stats' ? 'bg-stride-red/20' : ''}`} />
              <div className={`text-[8px] ${t === 'Stats' ? 'text-stride-red' : 'text-white/30'}`}>{t}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}

function StatCard({ label, value, sub, change }) {
  return (
    <div className="bg-[#1C1C1E] rounded-xl p-3">
      <div className="text-[9px] text-white/40 uppercase tracking-wide mb-1">{label}</div>
      <div className="font-barlow text-[28px] font-medium leading-none">{value}</div>
      <div className="text-[9px] text-white/30 mt-0.5">{sub}</div>
      {change && <div className="text-[9px] text-green-500 mt-1">{change}</div>}
    </div>
  )
}
