export default function CTA() {
  return (
    <section id="download" className="py-32 md:py-44 bg-bg-dark relative overflow-hidden text-center">
      {/* Glow */}
      <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[600px] h-[400px] bg-[radial-gradient(ellipse,rgba(255,38,23,0.12)_0%,transparent_60%)] pointer-events-none animate-pulse" />

      <div className="relative z-10 max-w-[1400px] mx-auto px-6">
        <h2
          data-reveal
          className="font-inter font-black text-[clamp(40px,7vw,80px)] leading-[0.95] text-white mb-6"
        >
          Ready to<br />
          <span className="text-gradient-red">run faster?</span>
        </h2>

        <p data-reveal data-reveal-delay="1" className="text-xl text-white/40 mb-12 font-light max-w-md mx-auto">
          Download Stride. Set your goal.<br />Let AI handle the rest.
        </p>

        <div data-reveal data-reveal-delay="2">
          <a
            href="#"
            className="inline-flex items-center gap-3 bg-stride-red text-white font-semibold text-lg px-12 py-5 rounded-[10px] hover:bg-stride-dark-red transition-all hover:-translate-y-0.5 hover:shadow-[0_16px_50px_rgba(255,38,23,0.35)]"
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor">
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
            </svg>
            Get the App
          </a>
        </div>

        <p data-reveal data-reveal-delay="3" className="mt-8 text-sm text-white/20">
          Available on iPhone. Requires Assault Runner for treadmill features.
        </p>
      </div>
    </section>
  )
}
