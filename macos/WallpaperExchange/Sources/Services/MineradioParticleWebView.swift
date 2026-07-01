import AppKit
import WebKit

@MainActor
final class MineradioParticleWebGLRegistry {
    static let shared = MineradioParticleWebGLRegistry()

    private let views = NSHashTable<MineradioParticleWebView>.weakObjects()

    private init() {}

    func register(_ view: MineradioParticleWebView) {
        views.add(view)
    }

    func unregister(_ view: MineradioParticleWebView) {
        views.remove(view)
    }

    func recordClick(at globalPoint: CGPoint) {
        for view in views.allObjects {
            view.recordClick(at: globalPoint)
        }
    }
}

@MainActor
final class MineradioParticleWebView: WKWebView {
    private let screenFrame: CGRect
    private var audioTimer: Timer?

    init(frame: CGRect, presetIndex: Int, config: ParticleWallpaperConfig, screenFrame: CGRect) {
        self.screenFrame = screenFrame

        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        super.init(frame: frame, configuration: configuration)

        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        setValue(false, forKey: "drawsBackground")
        allowsBackForwardNavigationGestures = false

        MineradioParticleWebGLRegistry.shared.register(self)
        loadHTMLString(Self.html(presetIndex: presetIndex, config: config.clamped), baseURL: nil)
        startAudioBridge()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func close() {
        audioTimer?.invalidate()
        audioTimer = nil
        MineradioParticleWebGLRegistry.shared.unregister(self)
        stopLoading()
        loadHTMLString("", baseURL: nil)
    }

    func recordClick(at globalPoint: CGPoint) {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return }
        let x = (globalPoint.x - screenFrame.minX) / screenFrame.width
        let y = 1.0 - ((globalPoint.y - screenFrame.minY) / screenFrame.height)
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return }
        evaluateJavaScript(Self.jsCall("wallpaperPushRipple", x, y), completionHandler: nil)
    }

    private func startAudioBridge() {
        audioTimer?.invalidate()
        audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pushAudioFrame()
            }
        }
        audioTimer?.tolerance = 0.010
    }

    private func pushAudioFrame() {
        let audio = AudioReactiveMonitor.shared
        let live = audio.hasRecentAudio ? 1.0 : 0.0
        evaluateJavaScript(
            Self.jsCall("wallpaperSetAudio", audio.level, audio.beat, live),
            completionHandler: nil
        )
    }

    private static func jsCall(_ name: String, _ values: Double...) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 5
        formatter.usesGroupingSeparator = false
        let args = values
            .map { formatter.string(from: NSNumber(value: $0)) ?? "0" }
            .joined(separator: ",")
        return "window.\(name)(\(args));"
    }

    private static func html(presetIndex: Int, config: ParticleWallpaperConfig) -> String {
        let density = number(config.density)
        let speed = number(config.speed)
        let brightness = number(config.brightness)
        return #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<style>
html,body,#stage{margin:0;width:100%;height:100%;overflow:hidden;background:#02040a}
#stage{display:block}
</style>
</head>
<body>
<canvas id="stage"></canvas>
<script>
(() => {
  const PRESET = \#(presetIndex);
  const CONFIG = {
    density: \#(density),
    speed: \#(speed),
    brightness: \#(brightness)
  };
  const canvas = document.getElementById('stage');
  const gl = canvas.getContext('webgl', {
    alpha: false,
    antialias: false,
    depth: false,
    stencil: false,
    preserveDrawingBuffer: false,
    premultipliedAlpha: false
  });
  if (!gl) {
    document.body.style.background = '#02040a';
    return;
  }

  let width = 1;
  let height = 1;
  let dpr = 1;
  let audioLevel = 0;
  let audioBeat = 0;
  let hasLiveAudio = 0;
  let lastNativeAudio = 0;
  let startTime = performance.now();
  const ripples = [];

  window.wallpaperSetAudio = (level, beat, live) => {
    audioLevel = Math.max(0, Math.min(1, Number(level) || 0));
    audioBeat = Math.max(0, Math.min(1, Number(beat) || 0));
    hasLiveAudio = Number(live) > 0.5 ? 1 : 0;
    lastNativeAudio = performance.now();
  };

  window.wallpaperPushRipple = (x, y) => {
    ripples.push({ x: Number(x) || 0.5, y: Number(y) || 0.5, t: (performance.now() - startTime) / 1000 });
    while (ripples.length > 4) ripples.shift();
  };

  function resize() {
    const nextDpr = Math.min(2, Math.max(1, window.devicePixelRatio || 1));
    const nextWidth = Math.max(2, Math.floor(innerWidth * nextDpr));
    const nextHeight = Math.max(2, Math.floor(innerHeight * nextDpr));
    if (nextWidth === width && nextHeight === height && nextDpr === dpr) return;
    width = nextWidth;
    height = nextHeight;
    dpr = nextDpr;
    canvas.width = width;
    canvas.height = height;
    canvas.style.width = innerWidth + 'px';
    canvas.style.height = innerHeight + 'px';
    gl.viewport(0, 0, width, height);
  }
  addEventListener('resize', resize, { passive: true });

  function shader(type, source) {
    const handle = gl.createShader(type);
    gl.shaderSource(handle, source);
    gl.compileShader(handle);
    if (!gl.getShaderParameter(handle, gl.COMPILE_STATUS)) {
      throw new Error(gl.getShaderInfoLog(handle) || 'Shader compile failed');
    }
    return handle;
  }

  function program(vertex, fragment) {
    const handle = gl.createProgram();
    gl.attachShader(handle, shader(gl.VERTEX_SHADER, vertex));
    gl.attachShader(handle, shader(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(handle);
    if (!gl.getProgramParameter(handle, gl.LINK_STATUS)) {
      throw new Error(gl.getProgramInfoLog(handle) || 'Program link failed');
    }
    return handle;
  }

  function setRippleUniforms(handle, now) {
    const data = new Float32Array(16);
    for (let i = 0; i < 4; i += 1) {
      const r = ripples[ripples.length - 1 - i];
      if (!r) {
        data[i * 4 + 2] = 99;
        continue;
      }
      data[i * 4 + 0] = r.x;
      data[i * 4 + 1] = r.y;
      data[i * 4 + 2] = now - r.t;
      data[i * 4 + 3] = 1;
    }
    gl.uniform4fv(gl.getUniformLocation(handle, 'uRipples'), data);
  }

  function audioEnvelope(now) {
    const idle = 0.5 + 0.5 * Math.sin(now * 1.7 + Math.sin(now * 0.21) * 1.4);
    const nativeIsFresh = performance.now() - lastNativeAudio < 1200;
    const level = nativeIsFresh && hasLiveAudio
      ? audioLevel
      : 0.13 + idle * 0.12 + 0.04 * Math.sin(now * 0.43);
    const beat = nativeIsFresh && hasLiveAudio
      ? audioBeat
      : Math.max(0, Math.pow(0.5 + 0.5 * Math.sin(now * 1.95), 18.0) * 0.62);
    return {
      level: Math.max(0, Math.min(1, level)),
      beat: Math.max(0, Math.min(1, beat))
    };
  }

  const particleVertex = `
precision highp float;
attribute vec2 aUv;
attribute float aRand;
uniform float uTime;
uniform float uPreset;
uniform float uLevel;
uniform float uBeat;
uniform float uSpeed;
uniform float uBrightness;
uniform float uAspect;
uniform float uDpr;
uniform vec4 uRipples[4];
varying vec3 vColor;
varying float vAlpha;
varying float vGlow;

#define PI 3.14159265359

float hash(float n) { return fract(sin(n) * 43758.5453123); }
float noise(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float n = i.x + i.y * 57.0 + i.z * 113.0;
  return mix(
    mix(mix(hash(n + 0.0), hash(n + 1.0), f.x), mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
    mix(mix(hash(n + 113.0), hash(n + 114.0), f.x), mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y),
    f.z
  ) * 2.0 - 1.0;
}

float rippleAt(vec2 uv) {
  float sum = 0.0;
  for (int i = 0; i < 4; i++) {
    vec4 r = uRipples[i];
    if (r.z > 2.0 || r.w < 0.1) continue;
    float d = distance(uv, r.xy);
    float ring = exp(-pow((d - r.z * 0.48) / (0.055 + r.z * 0.035), 2.0));
    float core = exp(-d * d / (0.020 + r.z * 0.16));
    float fade = 1.0 - smoothstep(0.2, 2.0, r.z);
    sum += (ring * 0.9 + core * 0.55) * fade;
  }
  return sum;
}

vec3 palette(float n, float glow) {
  vec3 cool = mix(vec3(0.04, 0.28, 0.95), vec3(0.32, 0.92, 1.0), n);
  vec3 warm = mix(vec3(0.56, 0.12, 0.95), vec3(1.0, 0.28, 0.18), n);
  return mix(cool, warm, glow);
}

void main() {
  float t = uTime * (0.45 + uSpeed * 1.35);
  float bass = max(uLevel, 0.03);
  float beat = max(uBeat, 0.0);
  vec2 uv = aUv;
  vec2 p = (uv - 0.5) * 2.0;
  vec3 pos = vec3(0.0);
  vec2 clip = vec2(0.0);
  float alpha = 1.0;
  float point = 1.65;
  float glow = 0.25 + bass * 0.8 + beat * 0.8;

  if (uPreset < 0.5) {
    float warp = noise(vec3(p * 1.6, t * 0.22)) * 0.10;
    float fold = noise(vec3(p * 3.2 + vec2(1.7, -2.1), t * 0.34));
    float r = rippleAt(uv);
    clip = vec2(
      p.x + warp * 0.22 + sin(p.y * 5.0 + t * 0.7) * bass * 0.025,
      p.y + fold * bass * 0.18 + r * 0.035
    );
    clip.x /= max(1.0, uAspect);
    alpha = 0.34 + smoothstep(-0.2, 1.0, fold) * 0.42 + r * 0.35;
    point = 1.4 + bass * 4.5 + r * 7.0;
    vColor = palette(uv.y, 0.36 + uv.x * 0.25 + beat * 0.16);
  } else if (uPreset < 1.5) {
    float angle = uv.x * PI * 2.0 + t * 0.35;
    float flow = fract(uv.y - t * 0.055 * (1.0 + bass * 1.2));
    float z = (flow - 0.5) * 9.5;
    float radius = 1.7 + sin(angle * 5.0 + z * 1.2 + t) * (0.10 + bass * 0.22);
    pos = vec3(cos(angle) * radius, sin(angle) * radius, z);
    float depth = 4.6 - pos.z * 0.38;
    clip = pos.xy / max(0.7, depth);
    clip.x /= max(1.0, uAspect);
    alpha = 0.12 + smoothstep(0.0, 1.0, flow) * 0.78;
    point = 1.2 + (1.0 - flow) * 4.2 + beat * 3.4;
    vColor = palette(flow, 0.18 + bass * 0.65);
  } else if (uPreset < 2.5) {
    float theta = uv.x * PI * 2.0 + t * 0.11;
    float phi = (uv.y - 0.5) * PI;
    float r = 1.55 + bass * 0.48 + noise(vec3(theta, phi, t * 0.22)) * (0.14 + bass * 0.22);
    pos = vec3(r * cos(phi) * cos(theta), r * sin(phi), r * cos(phi) * sin(theta));
    float yaw = t * 0.22;
    float cy = cos(yaw);
    float sy = sin(yaw);
    pos.xz = mat2(cy, -sy, sy, cy) * pos.xz;
    float depth = 4.4 - pos.z * 0.52;
    clip = pos.xy / max(1.0, depth);
    clip.x /= max(1.0, uAspect);
    alpha = 0.18 + smoothstep(-0.8, 1.0, pos.z) * 0.68;
    point = 1.25 + bass * 4.0 + beat * 3.8;
    vColor = palette(uv.y, 0.24 + uv.x * 0.28 + beat * 0.24);
  } else if (uPreset < 4.5) {
    vec2 disc = p;
    disc.x *= min(1.0, uAspect);
    float spin = t * 0.55;
    float cs = cos(spin);
    float sn = sin(spin);
    vec2 rp = mat2(cs, -sn, sn, cs) * disc;
    float d = length(disc);
    float groove = 0.5 + 0.5 * sin(d * 90.0 + aRand * 10.0);
    float cover = 1.0 - smoothstep(0.33, 0.37, d);
    float record = 1.0 - smoothstep(0.72, 0.76, d);
    float rim = exp(-pow((d - 0.72) / 0.028, 2.0));
    clip = rp * (1.0 + beat * 0.018);
    alpha = record * (0.24 + groove * 0.42 + rim * 0.85);
    point = 1.45 + rim * 5.0 + beat * 3.4;
    vec3 vinyl = mix(vec3(0.035, 0.035, 0.040), vec3(0.18, 0.18, 0.20), groove * 0.45);
    vec3 label = palette(uv.x, 0.55 + bass * 0.2);
    vColor = mix(vinyl, label, cover * 0.92) + vec3(rim * 0.9);
  } else {
    float lane = uv.y;
    float seed = hash(aRand * 917.0);
    float band = floor(lane * 6.0);
    float local = fract(lane * 6.0);
    float flow = fract(uv.x + t * (0.010 + band * 0.002) + seed);
    float arc = (flow - 0.5) * PI * (1.25 + band * 0.12);
    float radius = 0.34 + band * 0.13 + local * 0.05;
    clip = vec2(
      cos(arc + band * 0.55) * radius + (flow - 0.5) * 0.52,
      (band / 5.0 - 0.5) * 0.86 + sin(arc * 1.8 + t * 0.28) * (0.06 + bass * 0.10)
    );
    clip.x += noise(vec3(flow * 2.0, lane * 2.0, t * 0.05)) * 0.065;
    clip.x /= max(1.0, uAspect);
    float ridge = exp(-pow((local - 0.5) / 0.22, 2.0));
    alpha = (0.12 + ridge * 0.72 + beat * 0.16) * smoothstep(0.02, 0.16, lane) * (1.0 - smoothstep(0.92, 1.0, lane));
    point = 1.15 + ridge * 4.2 + bass * 3.0;
    vColor = palette(band / 5.0, 0.34 + ridge * 0.25 + beat * 0.18);
  }

  float r = rippleAt(uv);
  clip += normalize(clip + vec2(0.0001)) * r * 0.018;
  vAlpha = clamp(alpha * (0.82 + uBrightness * 0.75), 0.0, 1.0);
  vGlow = glow + r;
  gl_Position = vec4(clip, 0.0, 1.0);
  gl_PointSize = max(1.0, point * uDpr * (0.82 + uBrightness * 0.8));
}
`;

  const particleFragment = `
precision highp float;
varying vec3 vColor;
varying float vAlpha;
varying float vGlow;
void main() {
  vec2 p = gl_PointCoord - 0.5;
  float d = length(p);
  float core = smoothstep(0.50, 0.02, d);
  float halo = smoothstep(0.50, 0.22, d) * 0.35;
  float alpha = (core + halo) * vAlpha;
  gl_FragColor = vec4(vColor * (0.70 + vGlow * 0.55), alpha);
}
`;

  const lineVertex = `
precision highp float;
attribute vec2 aPos;
attribute vec3 aColor;
attribute float aAlpha;
varying vec3 vColor;
varying float vAlpha;
void main() {
  vColor = aColor;
  vAlpha = aAlpha;
  gl_Position = vec4(aPos, 0.0, 1.0);
}
`;

  const lineFragment = `
precision highp float;
varying vec3 vColor;
varying float vAlpha;
void main() {
  gl_FragColor = vec4(vColor, vAlpha);
}
`;

  const planeVertex = `
precision highp float;
attribute vec2 aPos;
varying vec2 vUv;
void main() {
  vUv = aPos * 0.5 + 0.5;
  gl_Position = vec4(aPos, 0.0, 1.0);
}
`;

  const planeFragment = `
precision highp float;
uniform float uTime;
uniform float uLevel;
uniform float uBeat;
uniform float uPreset;
uniform float uBrightness;
uniform float uAspect;
uniform vec4 uRipples[4];
varying vec2 vUv;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float ripple(vec2 uv) {
  float sum = 0.0;
  for (int i = 0; i < 4; i++) {
    vec4 r = uRipples[i];
    if (r.z > 2.0 || r.w < 0.1) continue;
    float d = distance(uv, r.xy);
    float ring = exp(-pow((d - r.z * 0.42) / (0.04 + r.z * 0.035), 2.0));
    sum += ring * (1.0 - smoothstep(0.1, 2.0, r.z));
  }
  return sum;
}
void main() {
  vec2 uv = vUv;
  vec2 p = (uv - 0.5) * vec2(uAspect, 1.0);
  float t = uTime;
  float r = ripple(uv);
  vec3 color;
  if (uPreset < 8.5) {
    float cells = 0.0;
    for (int i = 0; i < 4; i++) {
      float fi = float(i);
      vec2 q = p * (3.2 + fi * 1.35) + vec2(t * (0.08 + fi * 0.02), -t * 0.05);
      float n = noise(q + noise(q * 0.7));
      cells += smoothstep(0.54, 0.92, n) / (fi + 1.4);
    }
    float glow = smoothstep(0.18, 0.82, cells + uLevel * 0.35 + r * 0.35);
    vec3 base = mix(vec3(0.015, 0.035, 0.105), vec3(0.04, 0.16, 0.34), uv.y);
    vec3 foam = mix(vec3(0.18, 0.42, 1.0), vec3(0.95, 0.34, 0.24), glow * 0.65 + uBeat * 0.25);
    color = base + foam * (glow * 0.9 + r * 0.5);
  } else {
    float fold = 0.0;
    vec2 q = p * 2.4;
    for (int i = 0; i < 5; i++) {
      q = abs(q) / max(0.35, dot(q, q)) - 0.62;
      fold += exp(-abs(length(q) - 1.1) * (2.0 + float(i) * 0.4));
    }
    float scan = 0.5 + 0.5 * sin((p.x * 8.0 + p.y * 5.0) + t * 0.55);
    float glow = smoothstep(0.65, 2.8, fold * 0.30 + scan * 0.35 + uLevel * 0.65 + r);
    vec3 base = mix(vec3(0.005, 0.015, 0.035), vec3(0.04, 0.02, 0.10), uv.y);
    vec3 hot = mix(vec3(0.06, 0.56, 1.0), vec3(1.0, 0.16, 0.12), glow * 0.55 + uBeat * 0.28);
    color = base + hot * (glow * 0.95 + r * 0.4);
  }
  color *= 0.72 + uBrightness * 0.92;
  gl_FragColor = vec4(color, 1.0);
}
`;

  class ParticleSystem {
    constructor() {
      this.handle = program(particleVertex, particleFragment);
      this.buffer = gl.createBuffer();
      const grid = Math.floor(118 + CONFIG.density * 96);
      const data = new Float32Array(grid * grid * 3);
      let cursor = 0;
      for (let y = 0; y < grid; y += 1) {
        for (let x = 0; x < grid; x += 1) {
          const nx = (x + 0.5) / grid;
          const ny = (y + 0.5) / grid;
          data[cursor++] = nx;
          data[cursor++] = ny;
          data[cursor++] = (((x * 73856093) ^ (y * 19349663)) >>> 0) / 4294967295;
        }
      }
      this.count = grid * grid;
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, data, gl.STATIC_DRAW);
    }

    render(now, audio) {
      gl.useProgram(this.handle);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      const stride = 12;
      const uv = gl.getAttribLocation(this.handle, 'aUv');
      const rand = gl.getAttribLocation(this.handle, 'aRand');
      gl.enableVertexAttribArray(uv);
      gl.vertexAttribPointer(uv, 2, gl.FLOAT, false, stride, 0);
      gl.enableVertexAttribArray(rand);
      gl.vertexAttribPointer(rand, 1, gl.FLOAT, false, stride, 8);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uTime'), now);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uPreset'), PRESET);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uLevel'), audio.level);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uBeat'), audio.beat);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uSpeed'), CONFIG.speed);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uBrightness'), CONFIG.brightness);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uAspect'), width / Math.max(1, height));
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uDpr'), dpr);
      setRippleUniforms(this.handle, now);
      gl.drawArrays(gl.POINTS, 0, this.count);
    }
  }

  class PillarTerrain {
    constructor() {
      this.handle = program(lineVertex, lineFragment);
      this.buffer = gl.createBuffer();
      this.grid = Math.floor(72 + CONFIG.density * 52);
      this.points = [];
      this.lastAutoRipple = -10;
      for (let y = 0; y < this.grid; y += 1) {
        for (let x = 0; x < this.grid; x += 1) {
          const cx = (x - this.grid / 2 + 0.5) / this.grid * 2.0;
          const cz = (y - this.grid / 2 + 0.5) / this.grid * 2.0;
          const dist = Math.sqrt(cx * cx + cz * cz);
          if (dist > 1.05) continue;
          const rnd = ((x * 374761393 + y * 668265263) >>> 0) / 4294967295;
          this.points.push({ cx, cz, dist, rnd, falloff: Math.max(0.05, 1.0 - dist / 1.08) });
        }
      }
      this.data = new Float32Array(this.points.length * 6 * 6);
    }

    render(now, audio) {
      if (audio.beat > 0.46 && now - this.lastAutoRipple > 0.42) {
        const a = now * 1.37;
        const radius = 0.14 + (Math.sin(now * 0.71) * 0.5 + 0.5) * 0.22;
        ripples.push({
          x: 0.5 + Math.cos(a) * radius,
          y: 0.5 + Math.sin(a * 1.23) * radius,
          t: now
        });
        while (ripples.length > 4) ripples.shift();
        this.lastAutoRipple = now;
      }
      const aspect = width / Math.max(1, height);
      const angle = now * (0.08 + CONFIG.speed * 0.12);
      const ca = Math.cos(angle);
      const sa = Math.sin(angle);
      let cursor = 0;
      const columnWidth = Math.max(0.0018, 1.30 / this.grid / Math.max(1.0, aspect));
      for (const p of this.points) {
        const rx = p.cx * ca - p.cz * sa;
        const rz = p.cx * sa + p.cz * ca;
        const uvx = (p.cx + 1.0) * 0.5;
        const uvy = (p.cz + 1.0) * 0.5;
        let rippleLift = 0;
        for (const r of ripples) {
          const age = now - r.t;
          if (age < 0 || age > 2.0) continue;
          const dx = uvx - r.x;
          const dy = uvy - r.y;
          const dist = Math.sqrt(dx * dx + dy * dy);
          const ring = Math.exp(-Math.pow((dist - age * 0.35) / (0.026 + age * 0.022), 2.0));
          const core = Math.exp(-(dist * dist) / (0.012 + age * 0.12));
          rippleLift += (ring * 0.8 + core * 0.36) * (1.0 - Math.min(1, age / 2.0));
        }
        const wave = Math.sin(p.dist * 18.0 - now * 2.2 + p.rnd * 6.28) * 0.5 + 0.5;
        const ripple = Math.sin((rx * 7.0 + rz * 5.0) + now * 1.4) * 0.5 + 0.5;
        const h = (0.06 + p.falloff * 0.30)
          + audio.level * (0.20 + p.falloff * 0.72)
          + audio.beat * p.falloff * 0.58
          + wave * ripple * 0.18 * CONFIG.speed
          + rippleLift * (0.28 + audio.level * 0.35);
        const perspective = 1.0 / (1.12 + (rz + 1.0) * 0.32);
        const sx = (rx * 0.96 * perspective) / Math.max(1.0, aspect);
        const baseY = -0.50 + rz * 0.38 * perspective;
        const topY = baseY + h * (0.88 + perspective * 0.40);
        const glow = Math.min(1, p.falloff * 0.7 + audio.level * 0.8 + audio.beat * 0.8);
        const cool = [0.11 + glow * 0.10, 0.12 + glow * 0.20, 0.78 + glow * 0.20];
        const warm = [0.95, 0.18 + glow * 0.15, 0.88];
        const mixv = Math.min(1, Math.max(0, wave * 0.35 + audio.beat * 0.45 + p.rnd * 0.20));
        const color = [
          cool[0] * (1 - mixv) + warm[0] * mixv,
          cool[1] * (1 - mixv) + warm[1] * mixv,
          cool[2] * (1 - mixv) + warm[2] * mixv
        ];
        const alpha = (0.20 + p.falloff * 0.56 + audio.level * 0.24 + rippleLift * 0.32) * CONFIG.brightness;
        const widthScale = columnWidth * (0.55 + perspective * 1.25) * (0.9 + glow * 0.35);
        cursor = this.writeColumn(cursor, sx, baseY, topY, widthScale, color, alpha);
      }
      gl.useProgram(this.handle);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, this.data.subarray(0, cursor), gl.DYNAMIC_DRAW);
      const stride = 24;
      const pos = gl.getAttribLocation(this.handle, 'aPos');
      const color = gl.getAttribLocation(this.handle, 'aColor');
      const alpha = gl.getAttribLocation(this.handle, 'aAlpha');
      gl.enableVertexAttribArray(pos);
      gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, stride, 0);
      gl.enableVertexAttribArray(color);
      gl.vertexAttribPointer(color, 3, gl.FLOAT, false, stride, 8);
      gl.enableVertexAttribArray(alpha);
      gl.vertexAttribPointer(alpha, 1, gl.FLOAT, false, stride, 20);
      gl.drawArrays(gl.TRIANGLES, 0, cursor / 6);
    }

    writeColumn(cursor, x, baseY, topY, width, color, alpha) {
      const left = x - width;
      const right = x + width;
      const shade = [color[0] * 0.48, color[1] * 0.52, color[2] * 0.62];
      cursor = this.writeVertex(cursor, left, baseY, shade, alpha * 0.18);
      cursor = this.writeVertex(cursor, right, baseY, shade, alpha * 0.26);
      cursor = this.writeVertex(cursor, right, topY, color, alpha);
      cursor = this.writeVertex(cursor, left, baseY, shade, alpha * 0.18);
      cursor = this.writeVertex(cursor, right, topY, color, alpha);
      cursor = this.writeVertex(cursor, left, topY, color, alpha * 0.86);
      return cursor;
    }

    writeVertex(cursor, x, y, color, alpha) {
      this.data[cursor++] = x;
      this.data[cursor++] = y;
      this.data[cursor++] = color[0];
      this.data[cursor++] = color[1];
      this.data[cursor++] = color[2];
      this.data[cursor++] = alpha;
      return cursor;
    }
  }

  class PlaneSystem {
    constructor() {
      this.handle = program(planeVertex, planeFragment);
      this.buffer = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([
        -1, -1, 3, -1, -1, 3
      ]), gl.STATIC_DRAW);
    }

    render(now, audio) {
      gl.useProgram(this.handle);
      gl.bindBuffer(gl.ARRAY_BUFFER, this.buffer);
      const pos = gl.getAttribLocation(this.handle, 'aPos');
      gl.enableVertexAttribArray(pos);
      gl.vertexAttribPointer(pos, 2, gl.FLOAT, false, 8, 0);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uTime'), now * (0.45 + CONFIG.speed));
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uLevel'), audio.level);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uBeat'), audio.beat);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uPreset'), PRESET);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uBrightness'), CONFIG.brightness);
      gl.uniform1f(gl.getUniformLocation(this.handle, 'uAspect'), width / Math.max(1, height));
      setRippleUniforms(this.handle, now);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
    }
  }

  let renderer;
  if (PRESET === 7) renderer = new PillarTerrain();
  else if (PRESET === 8 || PRESET === 9) renderer = new PlaneSystem();
  else renderer = new ParticleSystem();

  gl.disable(gl.DEPTH_TEST);
  gl.enable(gl.BLEND);

  let lastPaint = 0;
  function frame(stamp) {
    resize();
    const now = (stamp - startTime) / 1000;
    requestAnimationFrame(frame);
    if (stamp - lastPaint < 1000 / 34) return;
    lastPaint = stamp;
    const audio = audioEnvelope(now);
    if (PRESET === 7) gl.clearColor(0.006, 0.002, 0.020, 1);
    else gl.clearColor(0.002, 0.004, 0.010, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);
    if (PRESET === 8 || PRESET === 9) {
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    } else {
      gl.blendFunc(gl.SRC_ALPHA, gl.ONE);
    }
    renderer.render(now, audio);
  }
  requestAnimationFrame(frame);
})();
</script>
</body>
</html>
"""#
    }

    private static func number(_ value: Double) -> String {
        String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
