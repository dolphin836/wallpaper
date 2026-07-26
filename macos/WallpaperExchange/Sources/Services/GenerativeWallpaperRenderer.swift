import AppKit
import MetalKit
import SwiftUI

private struct GenerativeUniforms {
    var resolution: SIMD2<Float>
    var time: Float
    var preset: UInt32
    var intensity: Float
    var speed: Float
    var pointer: SIMD2<Float>
}

private final class GenerativeMetalPipeline {
    static let shared: GenerativeMetalPipeline? = GenerativeMetalPipeline()

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else { return nil }

        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            guard let vertex = library.makeFunction(name: "generativeVertex"),
                  let fragment = library.makeFunction(name: "generativeFragment") else { return nil }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Generative Wallpaper Pipeline"
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
            self.device = device
            self.commandQueue = commandQueue
        } catch {
            assertionFailure("Could not compile generative wallpaper shaders: \(error)")
            return nil
        }
    }

    private static let shaderSource = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct Uniforms {
        float2 resolution;
        float time;
        uint preset;
        float intensity;
        float speed;
        float2 pointer;
    };

    vertex VertexOut generativeVertex(uint vertexID [[vertex_id]]) {
        float2 positions[3] = {
            float2(-1.0, -1.0),
            float2( 3.0, -1.0),
            float2(-1.0,  3.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    float hash11(float p) {
        p = fract(p * 0.1031);
        p *= p + 33.33;
        p *= p + p;
        return fract(p);
    }

    float hash21(float2 p) {
        float3 p3 = fract(float3(p.xyx) * 0.1031);
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.x + p3.y) * p3.z);
    }

    float2 hash22(float2 p) {
        float3 p3 = fract(float3(p.xyx) * float3(0.1031, 0.1030, 0.0973));
        p3 += dot(p3, p3.yzx + 33.33);
        return fract((p3.xx + p3.yz) * p3.zy);
    }

    float noise2(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        return mix(mix(hash21(i), hash21(i + float2(1.0, 0.0)), f.x),
                   mix(hash21(i + float2(0.0, 1.0)), hash21(i + 1.0), f.x), f.y);
    }

    float fbm(float2 p) {
        float value = 0.0;
        float amplitude = 0.5;
        for (int i = 0; i < 5; i++) {
            value += noise2(p) * amplitude;
            p = p * 2.03 + float2(17.1, 9.2);
            amplitude *= 0.5;
        }
        return value;
    }

    float vignette(float2 uv) {
        float2 q = uv * (1.0 - uv);
        return pow(clamp(q.x * q.y * 17.0, 0.0, 1.0), 0.24);
    }

    float3 deepField(float2 uv, float2 p, float t, float intensity, float2 pointer) {
        float drift = t * 0.014;
        float cloudA = fbm(p * 1.15 + float2(drift, -drift * 0.55));
        float cloudB = fbm(p * 2.4 - float2(drift * 0.45, drift));
        float nebula = smoothstep(0.34, 0.88, cloudA * 0.72 + cloudB * 0.36);
        float3 color = mix(float3(0.006, 0.009, 0.026), float3(0.018, 0.060, 0.145), uv.y);
        color += float3(0.020, 0.072, 0.160) * nebula * 0.72;
        color += float3(0.050, 0.012, 0.110) * smoothstep(0.58, 0.95, cloudB) * 0.34;

        for (int layer = 0; layer < 4; layer++) {
            float depth = float(layer) / 3.0;
            float scale = mix(28.0, 82.0, depth);
            float2 shifted = uv + pointer * mix(0.002, 0.010, depth);
            shifted += float2(drift * mix(0.08, 0.32, depth), -drift * 0.04);
            float2 grid = shifted * scale;
            float2 cell = floor(grid);
            float2 local = fract(grid) - 0.5;
            float2 seed = cell + float2(71.0 * float(layer), 29.0 * float(layer));
            float2 starOffset = hash22(seed) - 0.5;
            float radius = length(local - starOffset);
            float rarity = step(mix(0.72, 0.48, depth), hash21(seed + 8.7));
            float size = mix(0.020, 0.070, hash21(seed + 2.4)) * mix(0.68, 1.0, depth);
            float core = 1.0 - smoothstep(size * 0.18, size, radius);
            float halo = size * size * 0.085 / (radius * radius + 0.0014);
            float twinkle = 0.62 + 0.38 * sin(t * mix(0.65, 1.75, hash21(seed + 4.8)) + hash21(seed) * 6.2831);
            float warmth = hash21(seed + 11.1);
            float3 starColor = mix(float3(0.54, 0.72, 1.0), float3(1.0, 0.86, 0.65), smoothstep(0.82, 1.0, warmth));
            color += starColor * (core + halo * 0.24) * rarity * twinkle * mix(0.35, 1.15, depth) * intensity;
        }

        float shotPhase = fract(t * 0.026);
        float shotLife = 1.0 - smoothstep(0.0, 0.34, abs(shotPhase - 0.16));
        float2 shotOrigin = float2(-0.9 + shotPhase * 3.6, 0.58 - shotPhase * 1.2);
        float2 shotDelta = p - shotOrigin;
        float shotLine = exp(-abs(shotDelta.y + shotDelta.x * 0.34) * 260.0)
            * smoothstep(0.36, -0.08, shotDelta.x) * smoothstep(-0.92, -0.04, shotDelta.x);
        color += float3(0.62, 0.82, 1.0) * shotLine * shotLife * 0.42;
        return color * mix(0.72, 1.0, vignette(uv));
    }

    float rainLayer(float2 uv, float t, float scale, float seed) {
        float2 q = uv * float2(scale, scale * 0.52);
        q.x += sin(q.y * 0.13 + seed) * 0.18;
        float column = floor(q.x);
        float random = hash11(column + seed * 17.0);
        float speed = mix(0.45, 1.15, random);
        float y = fract(q.y + t * speed + random * 7.0);
        float x = fract(q.x) - 0.5 - (hash11(column + 3.7 + seed) - 0.5) * 0.46;
        float head = length(float2(x * 1.9, (y - 0.08) * 4.2));
        float bead = 1.0 - smoothstep(0.045, 0.13, head);
        float trail = exp(-abs(x) * 36.0) * smoothstep(0.08, 0.22, y) * (1.0 - smoothstep(0.22, 0.93, y));
        trail *= pow(1.0 - y, 0.78);
        return (bead * 1.25 + trail * 0.72) * smoothstep(0.18, 0.96, random);
    }

    float glassDropField(float2 uv, float scale, float seed, float t) {
        float2 q = uv * scale;
        float2 cell = floor(q);
        float2 local = fract(q) - 0.5;
        float2 rnd = hash22(cell + seed);
        float2 center = (rnd - 0.5) * float2(0.56, 0.48);
        center.y += sin(t * 0.08 + rnd.x * 6.2831) * 0.018;
        local -= center;
        local.y += local.x * local.x * 0.72;
        float radius = mix(0.095, 0.205, rnd.x);
        float d = length(float2(local.x, local.y * 1.20));
        float rim = 1.0 - smoothstep(0.010, 0.030, abs(d - radius));
        float lens = (1.0 - smoothstep(radius * 0.20, radius * 0.92, d)) * 0.08;
        float highlight = exp(-length((local - float2(-radius * 0.34, radius * 0.28)) / radius) * 10.0);
        float runoff = exp(-abs(local.x) * 55.0)
            * smoothstep(-radius * 2.4, -radius * 0.7, local.y)
            * (1.0 - smoothstep(-radius * 0.65, -radius * 0.1, local.y));
        float rarity = smoothstep(0.52, 0.94, hash21(cell + seed * 4.7));
        return (rim * 0.055 + lens + highlight * 0.38 + runoff * 0.13) * rarity;
    }

    float3 rainWindow(float2 uv, float2 p, float t, float intensity, float2 pointer) {
        float horizon = smoothstep(0.12, 0.88, uv.y);
        float3 color = mix(float3(0.008, 0.024, 0.034), float3(0.018, 0.095, 0.145), horizon);
        float haze = fbm(p * 1.75 + float2(t * 0.018, 0.0));
        color += float3(0.018, 0.115, 0.155) * smoothstep(0.38, 0.88, haze) * 0.66;
        color += float3(0.055, 0.24, 0.32) * exp(-pow((uv.y - 0.34) * 4.4, 2.0)) * 0.32;

        float fine = rainLayer(uv + pointer * 0.004, t * 0.48, 34.0, 1.0);
        float middle = rainLayer(uv + float2(0.017, 0.0), t * 0.38, 22.0, 9.0);
        float near = rainLayer(uv + float2(-0.027, 0.0), t * 0.28, 13.0, 21.0);
        float rain = fine * 0.38 + middle * 0.62 + near * 0.90;
        color += mix(float3(0.24, 0.54, 0.68), float3(0.68, 0.93, 1.0), near) * rain * intensity;

        float drops = glassDropField(uv, 4.6, 7.0, t)
            + glassDropField(uv + float2(0.071, 0.039), 7.8, 31.0, t) * 0.52;
        color += float3(0.45, 0.82, 0.92) * drops * 0.34 * intensity;
        return color * mix(0.66, 1.0, vignette(uv));
    }

    float flameTongue(
        float2 p,
        float t,
        float phase,
        float xOffset,
        float widthScale,
        float heightScale
    ) {
        float2 q = p;
        q.x -= xOffset;
        q.y += 0.52;
        float y = clamp(q.y / heightScale, 0.0, 1.0);
        float sway = (fbm(float2(q.x * 3.2 + phase, q.y * 2.4 - t * 0.88 + phase)) - 0.5) * 0.23;
        sway += sin(q.y * 8.5 - t * 1.28 + phase) * mix(0.022, 0.074, y);
        float width = widthScale * mix(0.38, 0.010, pow(y, 0.72));
        float edge = abs(q.x + sway) - width;
        float mask = (1.0 - smoothstep(-0.018, 0.038, edge))
            * smoothstep(-0.035, 0.10, q.y)
            * (1.0 - smoothstep(heightScale * 0.78, heightScale, q.y));
        float tear = fbm(float2(q.x * 5.8 + phase * 2.0, q.y * 3.8 - t * 1.16));
        return mask * smoothstep(0.16 + y * 0.18, 0.64, tear + mask * 0.38);
    }

    float3 emberRoom(float2 uv, float2 p, float t, float intensity) {
        float3 color = mix(float3(0.010, 0.006, 0.008), float3(0.034, 0.010, 0.012), 1.0 - uv.y);
        float mainFlame = flameTongue(p, t, 1.7, 0.0, 1.0, 1.16);
        float leftFlame = flameTongue(p, t, 5.2, -0.17, 0.53, 0.80);
        float rightFlame = flameTongue(p, t, 9.4, 0.19, 0.58, 0.88);
        float highFlame = flameTongue(p, t, 13.1, 0.055, 0.42, 1.34);
        float outer = max(max(mainFlame, leftFlame), max(rightFlame, highFlame));

        float2 innerP = p;
        innerP.y += 0.02;
        float middle = flameTongue(innerP, t, 3.3, -0.025, 0.61, 0.77);
        float core = flameTongue(innerP, t, 7.8, 0.035, 0.34, 0.52);
        float height = clamp((p.y + 0.52) / 1.22, 0.0, 1.0);
        float3 outerColor = mix(float3(0.69, 0.030, 0.008), float3(1.0, 0.24, 0.018), 1.0 - height);
        color += outerColor * outer * 1.42 * intensity;
        color += float3(1.0, 0.37, 0.035) * middle * 1.22 * intensity;
        color += float3(1.0, 0.91, 0.36) * core * 1.42 * intensity;

        float coalNoise = fbm(float2(p.x * 10.0 - t * 0.08, p.y * 18.0));
        float coalBand = exp(-abs(p.y + 0.51) * 34.0)
            * (1.0 - smoothstep(0.18, 0.52, abs(p.x)))
            * smoothstep(0.25, 0.82, coalNoise);
        color += mix(float3(0.55, 0.025, 0.006), float3(1.0, 0.43, 0.06), coalNoise) * coalBand * intensity;

        float groundGlow = exp(-length(float2(p.x * 0.70, (p.y + 0.52) * 2.5)) * 2.35);
        color += float3(0.34, 0.030, 0.006) * groundGlow * 0.88 * intensity;

        for (int layer = 0; layer < 3; layer++) {
            float scale = 8.0 + float(layer) * 5.0;
            float2 q = float2((p.x + 0.68) * scale, (p.y + 0.52 + t * (0.13 + float(layer) * 0.025)) * scale);
            float2 cell = floor(q);
            float2 local = fract(q) - 0.5;
            float rnd = hash21(cell + float2(17.0 * float(layer), 4.0));
            float2 offset = (hash22(cell + 8.1) - 0.5) * 0.70;
            float d = length(local - offset);
            float ember = (1.0 - smoothstep(0.016, 0.076, d)) * smoothstep(0.74, 0.97, rnd);
            float centerBias = exp(-abs(p.x) * 2.8) * smoothstep(-0.45, 0.62, p.y) * (1.0 - smoothstep(0.55, 1.0, p.y));
            color += mix(float3(1.0, 0.18, 0.02), float3(1.0, 0.86, 0.28), rnd) * ember * centerBias * intensity;
        }
        return color * mix(0.70, 1.0, vignette(uv));
    }

    float fireflyLayer(float2 p, float t, float scale, float seed, float intensity) {
        float2 q = p * scale;
        float2 cell = floor(q);
        float2 local = fract(q) - 0.5;
        float2 rnd = hash22(cell + seed);
        float2 wander = (rnd - 0.5) * 0.54;
        wander += float2(sin(t * (0.24 + rnd.x * 0.31) + rnd.y * 8.0),
                         cos(t * (0.18 + rnd.y * 0.27) + rnd.x * 7.0)) * 0.16;
        float d = length(local - wander);
        float pulse = pow(0.5 + 0.5 * sin(t * (0.55 + rnd.x) + hash21(cell + 4.0) * 6.2831), 3.0);
        float rarity = smoothstep(0.66, 0.96, hash21(cell + seed * 3.2));
        float core = 1.0 - smoothstep(0.018, 0.060, d);
        float glow = 0.0032 / (d * d + 0.0032);
        return (core * 1.7 + glow * 0.23) * pulse * rarity * intensity;
    }

    float3 fireflyHollow(float2 uv, float2 p, float t, float intensity, float2 pointer) {
        float3 color = mix(float3(0.006, 0.027, 0.022), float3(0.025, 0.115, 0.078), uv.y);
        float mist = fbm(p * 1.65 + float2(t * 0.018, -t * 0.006));
        color += float3(0.035, 0.115, 0.075) * smoothstep(0.30, 0.86, mist) * 0.62;
        float moonHaze = exp(-length((p - float2(0.42, 0.34)) * float2(0.72, 1.0)) * 1.7);
        color += float3(0.10, 0.17, 0.11) * moonHaze * 0.24;

        float2 moved = p + pointer * 0.025;
        float farLights = fireflyLayer(moved, t, 4.5, 4.0, intensity) * 0.42;
        float midLights = fireflyLayer(moved + float2(0.13, 0.07), t, 6.5, 19.0, intensity) * 0.72;
        float nearLights = fireflyLayer(moved - float2(0.08, 0.11), t, 8.2, 37.0, intensity);
        color += float3(0.50, 0.72, 0.12) * farLights;
        color += float3(0.75, 0.93, 0.22) * midLights;
        color += float3(1.0, 0.94, 0.42) * nearLights;

        float2 glowAPosition = float2(-0.48 + sin(t * 0.19) * 0.14, 0.04 + cos(t * 0.15) * 0.12);
        float2 glowBPosition = float2(0.62 + cos(t * 0.14) * 0.10, -0.18 + sin(t * 0.22) * 0.16);
        float2 glowAOffset = p - glowAPosition;
        float2 glowBOffset = p - glowBPosition;
        float glowAPulse = 0.46 + 0.54 * sin(t * 0.61 + 1.8);
        float glowBPulse = 0.48 + 0.52 * sin(t * 0.53 + 4.1);
        float glowA = 0.006 / (dot(glowAOffset, glowAOffset) + 0.006) * glowAPulse;
        float glowB = 0.009 / (dot(glowBOffset, glowBOffset) + 0.009) * glowBPulse;
        color += float3(0.72, 0.98, 0.22) * glowA * 0.72 * intensity;
        color += float3(1.0, 0.86, 0.22) * glowB * 0.62 * intensity;

        float leftTrunk = 1.0 - smoothstep(0.055, 0.105, abs(p.x + 1.46 + sin(p.y * 2.3) * 0.045));
        float rightTrunk = 1.0 - smoothstep(0.045, 0.095, abs(p.x - 1.50 + cos(p.y * 2.0) * 0.040));
        float trunks = max(leftTrunk, rightTrunk) * smoothstep(-0.82, 0.56, p.y);
        color = mix(color, float3(0.002, 0.012, 0.009), trunks * 0.74);

        float foreground = smoothstep(0.10, -0.10, p.y + 0.66 + noise2(p * 2.8) * 0.22);
        color = mix(color, float3(0.003, 0.014, 0.011), foreground * 0.86);
        return color * mix(0.66, 1.0, vignette(uv));
    }

    fragment float4 generativeFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
        float2 uv = in.uv;
        float aspect = max(u.resolution.x / max(u.resolution.y, 1.0), 1.0);
        float2 p = (uv - 0.5) * float2(aspect, 1.0) * 2.0;
        float t = u.time * mix(0.35, 1.35, clamp(u.speed, 0.0, 1.0));
        float intensity = mix(0.48, 1.22, clamp(u.intensity, 0.0, 1.0));
        float2 pointer = (u.pointer - 0.5) * 2.0;

        float3 color;
        if (u.preset == 0) {
            color = deepField(uv, p, t, intensity, pointer);
        } else if (u.preset == 1) {
            color = rainWindow(uv, p, t, intensity, pointer);
        } else if (u.preset == 2) {
            color = emberRoom(uv, p, t, intensity);
        } else {
            color = fireflyHollow(uv, p, t, intensity, pointer);
        }

        float grain = (hash21(in.position.xy + fract(t) * 127.0) - 0.5) / 255.0;
        color += grain;
        color = pow(max(color, 0.0), float3(0.92));
        return float4(clamp(color, 0.0, 1.0), 1.0);
    }
    """#
}

private final class GenerativeRenderer: NSObject, MTKViewDelegate {
    var preset: GenerativePreset
    var settings: GenerativeWallpaperSettings
    var pointer = SIMD2<Float>(repeating: 0.5)
    var targetPointer = SIMD2<Float>(repeating: 0.5)

    private let pipeline: GenerativeMetalPipeline
    private var elapsed: Float = 0
    private var lastTimestamp = CACurrentMediaTime()

    init?(preset: GenerativePreset, settings: GenerativeWallpaperSettings) {
        guard let pipeline = GenerativeMetalPipeline.shared else { return nil }
        self.preset = preset
        self.settings = settings
        self.pipeline = pipeline
        super.init()
    }

    func resetFrameClock() {
        lastTimestamp = CACurrentMediaTime()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = pipeline.commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let now = CACurrentMediaTime()
        elapsed += Float(min(max(now - lastTimestamp, 0), 0.1))
        lastTimestamp = now
        pointer += (targetPointer - pointer) * 0.045

        var uniforms = GenerativeUniforms(
            resolution: SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height)),
            time: elapsed,
            preset: preset.shaderIndex,
            intensity: settings.intensity,
            speed: settings.speed,
            pointer: pointer
        )

        encoder.setRenderPipelineState(pipeline.pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<GenerativeUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

final class GenerativeMetalView: MTKView {
    private let generativeRenderer: GenerativeRenderer
    private var mouseTrackingArea: NSTrackingArea?

    init?(
        frame: CGRect,
        preset: GenerativePreset,
        settings: GenerativeWallpaperSettings,
        framesPerSecond: Int,
        interactive: Bool
    ) {
        guard let pipeline = GenerativeMetalPipeline.shared,
              let renderer = GenerativeRenderer(preset: preset, settings: settings) else { return nil }
        generativeRenderer = renderer
        super.init(frame: frame, device: pipeline.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0)
        framebufferOnly = true
        preferredFramesPerSecond = framesPerSecond
        enableSetNeedsDisplay = false
        isPaused = false
        delegate = renderer
        layer?.isOpaque = true
        if !interactive {
            generativeRenderer.targetPointer = SIMD2<Float>(repeating: 0.5)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        preset: GenerativePreset,
        settings: GenerativeWallpaperSettings,
        framesPerSecond: Int,
        paused: Bool
    ) {
        generativeRenderer.preset = preset
        generativeRenderer.settings = settings
        preferredFramesPerSecond = framesPerSecond
        if isPaused != paused {
            isPaused = paused
            if !paused { generativeRenderer.resetFrameClock() }
        }
    }

    override func updateTrackingAreas() {
        if let mouseTrackingArea { removeTrackingArea(mouseTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInActiveApp, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        mouseTrackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, bounds.height > 0 else { return }
        generativeRenderer.targetPointer = SIMD2(
            Float(min(max(location.x / bounds.width, 0), 1)),
            Float(min(max(location.y / bounds.height, 0), 1))
        )
    }
}

struct GenerativeWallpaperPreview: NSViewRepresentable {
    let preset: GenerativePreset
    var settings: GenerativeWallpaperSettings = .standard
    var framesPerSecond = 20
    var paused = false
    var interactive = true

    func makeNSView(context: Context) -> GenerativeMetalView {
        guard let view = GenerativeMetalView(
            frame: .zero,
            preset: preset,
            settings: settings,
            framesPerSecond: effectiveFramesPerSecond,
            interactive: interactive
        ) else {
            preconditionFailure("Metal is required for generative wallpapers")
        }
        return view
    }

    func updateNSView(_ view: GenerativeMetalView, context: Context) {
        view.configure(
            preset: preset,
            settings: settings,
            framesPerSecond: effectiveFramesPerSecond,
            paused: paused || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    static func dismantleNSView(_ view: GenerativeMetalView, coordinator: Void) {
        view.isPaused = true
        view.delegate = nil
        view.releaseDrawables()
    }

    private var effectiveFramesPerSecond: Int {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : framesPerSecond
    }
}
