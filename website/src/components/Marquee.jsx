export default function Marquee() {
  const items = ['5K', '10K', 'HALF MARATHON', 'MARATHON', '50K', '80K', '100K', '160K', 'ULTRA']

  return (
    <div className="border-y border-white/[0.06] bg-bg-dark py-5 overflow-hidden">
      <div className="animate-marquee flex whitespace-nowrap">
        {[...items, ...items].map((item, i) => (
          <span key={i} className="flex items-center">
            <span className="font-barlow font-bold text-[15px] tracking-[0.25em] uppercase text-white/20 mx-8">
              {item}
            </span>
            <span className="w-1.5 h-1.5 bg-stride-red/40 rotate-45" />
          </span>
        ))}
      </div>
    </div>
  )
}
