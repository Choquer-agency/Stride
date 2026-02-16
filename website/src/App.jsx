import { useEffect } from 'react'
import Lenis from 'lenis'
import useReveal from './hooks/useReveal'
import Nav from './components/Nav'
import Hero from './components/Hero'
import Marquee from './components/Marquee'
import BrandStatement from './components/BrandStatement'
import AppShowcase from './components/AppShowcase'
import FeaturesTransition from './components/FeaturesTransition'
import Treadmill from './components/Treadmill'
import HowItWorks from './components/HowItWorks'
import Distances from './components/Distances'
import Testimonials from './components/Testimonials'
import CTA from './components/CTA'
import Footer from './components/Footer'
import StickyGetApp from './components/StickyGetApp'

export default function App() {
  // Lenis smooth scroll
  useEffect(() => {
    const lenis = new Lenis({
      duration: 1.2,
      easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
      smoothWheel: true,
    })

    function raf(time) {
      lenis.raf(time)
      requestAnimationFrame(raf)
    }
    requestAnimationFrame(raf)

    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach((anchor) => {
      anchor.addEventListener('click', (e) => {
        const href = anchor.getAttribute('href')
        if (href === '#') return
        e.preventDefault()
        const target = document.querySelector(href)
        if (target) lenis.scrollTo(target)
      })
    })

    return () => lenis.destroy()
  }, [])

  // Intersection Observer for scroll reveals
  useReveal()

  return (
    <>
      <Nav />
      <StickyGetApp />
      {/* DARK: Hero with video bg */}
      <Hero />
      {/* DARK: Distance marquee ticker */}
      <Marquee />
      {/* LIGHT: Brand statement + 3 staggered images (O+A style) */}
      <BrandStatement />
      {/* LIGHT: App screenshot grid */}
      <AppShowcase />
      {/* DARK: Features → Training Plan sticky scroll transition */}
      <FeaturesTransition />
      {/* DARK: Stats phone + metrics */}
      <Treadmill />
      {/* DARK: 4-step process */}
      <HowItWorks />
      {/* LIGHT: Distance cards */}
      <Distances />
      {/* LIGHT: Sliding testimonials */}
      <Testimonials />
      {/* DARK: Download CTA */}
      <CTA />
      {/* DARK: Footer */}
      <Footer />
    </>
  )
}
