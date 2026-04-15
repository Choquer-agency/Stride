import SwiftUI
import WebKit

/// WebGL "voice orb" shown while the AI coach is speaking the pre-run intro.
/// Wraps a WKWebView running Three.js. The inline HTML auto-starts a simulated
/// audio-reactive animation, so there's no Swift→JS audio piping to worry about —
/// the orb pulses believably on its own and goes away when the view is dismissed.
struct VoiceOrbView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        // Using a https base so the CDN-loaded three.js script runs under a secure origin.
        webView.loadHTMLString(Self.html, baseURL: URL(string: "https://cdnjs.cloudflare.com"))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private static let html: String = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1.0" />
      <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
        body { display: flex; align-items: center; justify-content: center; }
        #orb-wrapper {
          width: 150px;
          height: 150px;
          border-radius: 50%;
          overflow: hidden;
          position: relative;
          box-shadow:
            0 0 25px rgba(255, 220, 80, 0.95),
            0 0 55px rgba(255, 140, 40, 0.9),
            0 0 95px rgba(255, 80, 20, 0.75);
        }
        #canvas-container {
          width: 100%;
          height: 100%;
          filter: blur(1.2px);
          transform: scale(1.45);
          transform-origin: center;
        }
        canvas { display: block; width: 100%; height: 100%; }
      </style>
      <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
    </head>
    <body>
      <div id="orb-wrapper"><div id="canvas-container"></div></div>

      <script type="x-shader/x-vertex" id="vertexShader">
        uniform float u_time;
        uniform float u_frequency;

        varying float vNoise;
        varying float vDetail;
        varying vec3 vNormal;

        vec3 mod289(vec3 x){ return x - floor(x*(1.0/289.0))*289.0; }
        vec4 mod289(vec4 x){ return x - floor(x*(1.0/289.0))*289.0; }
        vec4 permute(vec4 x){ return mod289(((x*34.0)+1.0)*x); }
        vec4 taylorInvSqrt(vec4 r){ return 1.79284291400159 - 0.85373472095314 * r; }
        vec3 fade(vec3 t){ return t*t*t*(t*(t*6.0-15.0)+10.0); }

        float cnoise(vec3 P){
          vec3 Pi0 = floor(P);
          vec3 Pi1 = Pi0 + vec3(1.0);
          Pi0 = mod289(Pi0);
          Pi1 = mod289(Pi1);
          vec3 Pf0 = fract(P);
          vec3 Pf1 = Pf0 - vec3(1.0);

          vec4 ix = vec4(Pi0.x, Pi1.x, Pi0.x, Pi1.x);
          vec4 iy = vec4(Pi0.y, Pi0.y, Pi1.y, Pi1.y);
          vec4 iz0 = Pi0.zzzz;
          vec4 iz1 = Pi1.zzzz;

          vec4 ixy = permute(permute(ix)+iy);
          vec4 ixy0 = permute(ixy+iz0);
          vec4 ixy1 = permute(ixy+iz1);

          vec4 gx0 = ixy0*(1.0/7.0);
          vec4 gy0 = fract(floor(gx0)/7.0)-0.5;
          gx0 = fract(gx0);
          vec4 gz0 = 0.5 - abs(gx0) - abs(gy0);
          vec4 sz0 = step(gz0,vec4(0.0));
          gx0 -= sz0*(step(0.0,gx0)-0.5);
          gy0 -= sz0*(step(0.0,gy0)-0.5);

          vec4 gx1 = ixy1*(1.0/7.0);
          vec4 gy1 = fract(floor(gx1)/7.0)-0.5;
          gx1 = fract(gx1);
          vec4 gz1 = 0.5 - abs(gx1) - abs(gy1);
          vec4 sz1 = step(gz1,vec4(0.0));
          gx1 -= sz1*(step(0.0,gx1)-0.5);
          gy1 -= sz1*(step(0.0,gy1)-0.5);

          vec3 g000 = vec3(gx0.x,gy0.x,gz0.x);
          vec3 g100 = vec3(gx0.y,gy0.y,gz0.y);
          vec3 g010 = vec3(gx0.z,gy0.z,gz0.z);
          vec3 g110 = vec3(gx0.w,gy0.w,gz0.w);
          vec3 g001 = vec3(gx1.x,gy1.x,gz1.x);
          vec3 g101 = vec3(gx1.y,gy1.y,gz1.y);
          vec3 g011 = vec3(gx1.z,gy1.z,gz1.z);
          vec3 g111 = vec3(gx1.w,gy1.w,gz1.w);

          vec4 norm0 = taylorInvSqrt(vec4(dot(g000,g000), dot(g100,g100), dot(g010,g010), dot(g110,g110)));
          g000*=norm0.x; g100*=norm0.y; g010*=norm0.z; g110*=norm0.w;

          vec4 norm1 = taylorInvSqrt(vec4(dot(g001,g001), dot(g101,g101), dot(g011,g011), dot(g111,g111)));
          g001*=norm1.x; g101*=norm1.y; g011*=norm1.z; g111*=norm1.w;

          float n000 = dot(g000,Pf0);
          float n100 = dot(g100,vec3(Pf1.x,Pf0.y,Pf0.z));
          float n010 = dot(g010,vec3(Pf0.x,Pf1.y,Pf0.z));
          float n110 = dot(g110,vec3(Pf1.xy,Pf0.z));
          float n001 = dot(g001,vec3(Pf0.xy,Pf1.z));
          float n101 = dot(g101,vec3(Pf1.x,Pf0.y,Pf1.z));
          float n011 = dot(g011,vec3(Pf0.x,Pf1.yz));
          float n111 = dot(g111,Pf1);

          vec3 fade_xyz = fade(Pf0);
          vec4 n_z = mix(vec4(n000,n100,n010,n110), vec4(n001,n101,n011,n111), fade_xyz.z);
          vec2 n_yz = mix(n_z.xy,n_z.zw,fade_xyz.y);
          float n_xyz = mix(n_yz.x,n_yz.y,fade_xyz.x);

          return 2.2*n_xyz;
        }

        void main() {
          vNormal = normalize(normalMatrix * normal);
          float baseNoise   = cnoise(vec3(position * 2.0 + u_time * 0.35));
          float detailNoise = cnoise(vec3(position * 4.5 + u_time * 4.0));
          float breathing   = sin(u_time * 1.4) * 0.04;
          float displacement = baseNoise * 0.16 + detailNoise * (0.25 + u_frequency * 0.95) + breathing * (0.5 + u_frequency);
          vNoise  = baseNoise;
          vDetail = detailNoise;
          vec3 newPos = position + normal * displacement;
          gl_Position = projectionMatrix * modelViewMatrix * vec4(newPos, 1.0);
        }
      </script>

      <script type="x-shader/x-fragment" id="fragmentShader">
        uniform float u_frequency;
        varying float vNoise;
        varying float vDetail;
        varying vec3 vNormal;

        void main() {
          // Fire palette — deep amber core, bright yellow swirl, molten orange edges,
          // red-hot highlights. All values >1.0 are fine; they get clamped at the end.
          vec3 cDeep    = vec3(0.90, 0.20, 0.05);  // ember red
          vec3 cOrange  = vec3(1.35, 0.55, 0.10);  // molten orange
          vec3 cYellow  = vec3(1.50, 1.15, 0.25);  // bright yellow
          vec3 cWhite   = vec3(1.60, 1.30, 0.70);  // hot white-yellow core

          vec3 nrm = normalize(vNormal);
          float angle  = atan(nrm.y, nrm.x);
          float swirl = sin(angle + vDetail * 1.5) * 0.5 + 0.5;
          float n = vNoise * 0.5 + vDetail * 0.5;

          vec3 palette = mix(cDeep, cOrange, smoothstep(0.0, 1.0, swirl));
          palette = mix(palette, cYellow, smoothstep(0.0, 1.0, n));
          palette = mix(palette, cWhite,  smoothstep(0.5, 1.0, (swirl + n) * 0.5));
          palette = pow(palette, vec3(0.75));

          vec3 color = palette;
          float facing = clamp((nrm.z + 1.0) * 0.5, 0.0, 1.0);
          color += facing * (0.04 + u_frequency * 0.06);

          float fresnel = pow(1.0 - dot(nrm, vec3(0.0, 0.0, 1.0)), 2.0);
          // Warm edge glow — saturated orange instead of white-blue.
          vec3 edgeGlow = vec3(1.2, 0.55, 0.15) * (0.28 + u_frequency * 0.4);
          color += edgeGlow * fresnel;

          color = clamp(color, 0.0, 1.0);
          gl_FragColor = vec4(color, 1.0);
        }
      </script>

      <script>
        let scene, camera, renderer, mesh, uniforms;
        let currentVol = 0, targetVol = 0;
        let simInterval, t = 0;

        function init() {
          const container = document.getElementById('canvas-container');
          const width = container.clientWidth;
          const height = container.clientHeight;

          scene = new THREE.Scene();
          camera = new THREE.PerspectiveCamera(45, width / height, 0.1, 100);
          camera.position.z = 2.2;

          renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
          renderer.setSize(width, height);
          renderer.setPixelRatio(window.devicePixelRatio || 1);
          renderer.setClearColor(0x000000, 0);
          container.appendChild(renderer.domElement);

          uniforms = { u_time: { value: 0.0 }, u_frequency: { value: 0.0 } };

          const geo = new THREE.IcosahedronGeometry(1.35, 9);
          const mat = new THREE.ShaderMaterial({
            uniforms,
            vertexShader: document.getElementById('vertexShader').textContent,
            fragmentShader: document.getElementById('fragmentShader').textContent,
          });

          mesh = new THREE.Mesh(geo, mat);
          scene.add(mesh);

          animate();
          startSim();
        }

        function animate() {
          requestAnimationFrame(animate);
          uniforms.u_time.value += 0.01 + uniforms.u_frequency.value * 0.02;
          mesh.rotation.y += 0.002;
          renderer.render(scene, camera);
          updateAudio();
        }

        function updateAudio() {
          targetVol = Math.min(0.7, Math.max(0.0, targetVol));
          currentVol += (targetVol - currentVol) * 0.18;
          uniforms.u_frequency.value = currentVol;
        }

        function startSim() {
          clearInterval(simInterval);
          simInterval = setInterval(() => {
            t += 0.15;
            let w = Math.sin(t * 0.8) * Math.cos(t * 2.5) + 0.6;
            if (Math.random() > 0.85) w *= 1.4;
            w = Math.max(0, w * 0.9);
            targetVol = Math.min(0.7, w);
          }, 60);
        }

        // Wait for three.js to finish loading before we init.
        if (window.THREE) { init(); } else { window.addEventListener('load', init); }
      </script>
    </body>
    </html>
    """
}
