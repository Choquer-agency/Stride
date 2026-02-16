export default function BrandStatement() {
  return (
    <section className="bg-bg-light min-h-screen flex flex-col justify-between py-16 md:py-20 overflow-hidden">
      <div className="max-w-[1400px] mx-auto px-6 w-full flex-1 flex flex-col">
        {/* Top area: large text + link — text takes ~55-60% width */}
        <div className="flex-1 flex flex-col justify-center">
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
            <div className="lg:col-span-7">
              <h2
                data-reveal
                className="font-inter font-bold text-[clamp(28px,3.8vw,52px)] leading-[1.12] text-brand-black"
              >
                Stride is an AI-powered running coach that sits at the intersection of sport science and technology, built for elite treadmill training.
              </h2>
              <a
                data-reveal
                data-reveal-delay="1"
                href="#features"
                className="inline-flex items-center gap-3 mt-8 font-barlow font-semibold text-[16px] tracking-[0.2em] uppercase text-brand-black hover:text-stride-red transition-colors"
              >
                Discover the Science
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                  <path d="M5 12h14M12 5l7 7-7 7" />
                </svg>
              </a>
            </div>

            <div className="hidden lg:flex lg:col-span-5 items-start justify-end">
              <p
                data-reveal
                data-reveal-delay="2"
                className="font-barlow font-semibold text-[16px] tracking-[0.2em] uppercase text-brand-black/30"
              >
                Become the Elite
              </p>
            </div>
          </div>
        </div>

        {/* 3 staggered images — smaller, bottom right, like O+A */}
        <div data-reveal data-reveal-delay="2" className="flex justify-end mt-12 md:mt-16">
          <div className="grid grid-cols-3 gap-3 md:gap-4 w-full max-w-[700px]">
            {/* Image 1 — offset down */}
            <div className="translate-y-6">
              <div className="aspect-[3/4] w-full overflow-hidden">
                <img
                  src="/photos/group-app.webp"
                  alt="Athletes with Stride app"
                  className="w-full h-full object-cover grayscale hover:grayscale-0 transition-all duration-700"
                />
              </div>
            </div>

            {/* Image 2 */}
            <div>
              <div className="aspect-[3/4] w-full overflow-hidden">
                <img
                  src="/photos/runner-portrait.webp"
                  alt="Athlete post-workout"
                  className="w-full h-full object-cover grayscale hover:grayscale-0 transition-all duration-700"
                />
              </div>
            </div>

            {/* Image 3 — offset up */}
            <div className="-translate-y-6">
              <div className="aspect-[3/4] w-full overflow-hidden">
                <img
                  src="/photos/runner-sprint-dark.webp"
                  alt="Runner sprinting"
                  className="w-full h-full object-cover grayscale hover:grayscale-0 transition-all duration-700"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  )
}
