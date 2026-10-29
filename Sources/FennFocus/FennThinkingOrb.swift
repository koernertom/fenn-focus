import SwiftUI

// Thinking orbs – a Swift port of the geometry in "thinking-orbs" by Jakub Antalík
// (https://github.com/Jakubantalik/thinking-orbs), MIT License:
//
//   Copyright (c) Jakub Antalík
//   Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
//   documentation files (the "Software"), to deal in the Software without restriction, including without limitation
//   the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//   permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright
//   notice and this permission notice shall be included in all copies or substantial portions of the Software.
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED.
//
// Four of its nine states are ported: working (orbits), searching (globe), listening (wave), breathing (ring),
// with the shipped 64 pt and 20 pt tunings.

/// What Fenn is doing right now – each state has its own motion.
enum OrbState {
    case working, searching, listening, breathing

    var label: String {
        switch self {
        case .working: return tr("Fenn denkt nach", "Fenn is thinking")
        case .searching: return tr("Fenn sucht", "Fenn is searching")
        case .listening: return tr("Fenn hört zu", "Fenn is listening")
        case .breathing: return tr("Atmen", "Breathing")
        }
    }
}

/// Dotted, depth-shaded, z-sorted 3D orb. Follows light/dark; `inverted` draws for the opposite surface
/// (e.g. inside the prominent pill, which is light in dark mode and dark in light mode).
struct ThinkingOrb: View {
    var state: OrbState = .working
    var size: CGFloat = 20
    var inverted = false
    @Environment(\.colorScheme) private var scheme
    private var onLight: Bool { (scheme == .light) != inverted }
    /// Breathing only: 0 = empty lungs, 1 = full – lets a breathing pace drive the ring's size.
    var level: Double? = nil
    /// Frames per second – a resting orb (slow breathing in the input) gets by with far fewer.
    var fps: Double = 30
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let preset = OrbPreset.resolve(state, size: size)
        TimelineView(.animation(minimumInterval: 1.0 / fps, paused: reduceMotion)) { context in
            let seconds = reduceMotion ? 2.0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            Canvas { g, canvas in
                let s = Double(min(canvas.width, canvas.height))
                var dots = OrbEngine.frame(preset, size: s, t: seconds * preset.speed)
                if let level, state == .breathing {
                    // Scale around the centre with the breath.
                    let k = 0.62 + 0.38 * max(0, min(1, level))
                    for i in dots.indices {
                        dots[i].x = s / 2 + (dots[i].x - s / 2) * k
                        dots[i].y = s / 2 + (dots[i].y - s / 2) * k
                    }
                }
                for d in dots {
                    let w = max(0, min(1, d.white))
                    let gray = onLight ? w : 1 - w
                    let rect = CGRect(x: d.x - d.r, y: d.y - d.r, width: d.r * 2, height: d.r * 2)
                    g.fill(Path(ellipseIn: rect), with: .color(Color(white: gray).opacity(d.a)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(state.label)
    }
}

// MARK: - Engine

struct OrbDot {
    var x: Double, y: Double, z: Double, r: Double
    /// Ink value on paper: 0 = darkest. Mirrored on dark surfaces.
    var white: Double
    var a: Double = 1
}

/// The shipped (state × size) tunings, already resolved from the base profiles and multipliers.
struct OrbPreset {
    enum Mode { case orbits, globe, wave, ring }
    let mode: Mode
    let speed: Double
    let o: [String: Double]

    func v(_ key: String, _ fallback: Double) -> Double { o[key] ?? fallback }

    static func resolve(_ state: OrbState, size: CGFloat) -> OrbPreset {
        let small = size <= 32
        switch state {
        case .working:
            return small
                ? OrbPreset(mode: .orbits, speed: 3.9, o: ["orbitN": 3, "ghostN": 10, "ghostR": 2.16, "ghostA": 0.5, "particles": 3,
                                                            "partR": 2.88, "partRDepth": 3.84, "rsPow": 0.6, "rMin": 0.3])
                : OrbPreset(mode: .orbits, speed: 1.885, o: ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3,
                                                              "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3])
        case .searching:
            return small
                ? OrbPreset(mode: .globe, speed: 2.665, o: ["latRings": 6, "lonDensity": 14, "rBase": 1.05, "rDepth": 2.975, "rBoost": 1,
                                                             "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3, "scanMul": 4.335, "dimBase": 0.45])
                : OrbPreset(mode: .globe, speed: 2.015, o: ["latRings": 11, "lonDensity": 29, "rBase": 0.69, "rDepth": 1.955, "rBoost": 1,
                                                             "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3, "scanMul": 4.08, "dimBase": 0.45])
        case .listening:
            return small
                ? OrbPreset(mode: .wave, speed: 3.998, o: ["rings": 5, "lonDensity": 13, "rBase": 0.96, "rDepth": 2.72, "rsPow": 0.6, "rMin": 0.3])
                : OrbPreset(mode: .wave, speed: 4.388, o: ["rings": 9, "lonDensity": 23, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3])
        case .breathing:
            return small
                ? OrbPreset(mode: .ring, speed: 3.78, o: ["lanes": 8, "segs": 15, "ghostN": 0, "faceOn": 1, "rBase": 1.7842, "rDepth": 2.7574,
                                                           "rsPow": 0.6, "rMin": 0.3, "spin": 0, "wobMul": 0.565])
                : OrbPreset(mode: .ring, speed: 3.24, o: ["lanes": 11, "segs": 44, "ghostN": 0, "faceOn": 1, "rBase": 1.0516, "rDepth": 1.6252,
                                                           "rsPow": 0.6, "rMin": 0.3, "spin": 0, "wobMul": 0.368])
        }
    }
}

enum OrbEngine {
    static func frame(_ p: OrbPreset, size: Double, t: Double) -> [OrbDot] {
        var dots: [OrbDot]
        switch p.mode {
        case .orbits: dots = orbits(size, t, p)
        case .globe: dots = globe(size, t, p)
        case .wave: dots = wave(size, t, p)
        case .ring: dots = ring(size, t, p)
        }
        // finalizeFrame: drop invisible marks, clamp radii, z-sort far → near.
        let rMin = p.v("rMin", 0.3)
        dots = dots.filter { $0.a >= 0.02 }
        for i in dots.indices { dots[i].r = max(rMin, dots[i].r) }
        dots.sort { $0.z < $1.z }
        return dots
    }

    // MARK: Primitives

    static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - floor(h)
    }

    static func angleDelta(_ a: Double, _ b: Double) -> Double { atan2(sin(a - b), cos(a - b)) }

    static func radiusScale(_ size: Double, _ pow: Double) -> Double { Foundation.pow(size / 300, pow) }

    /// Spin + tilt + orthographic projection.
    static func projector(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    // MARK: Orbits – working

    static func orbits(_ size: Double, _ t: Double, _ o: OrbPreset) -> [OrbDot] {
        let c = size / 2
        let R = c * 0.82
        let pt = projector(yaw: t * 0.12, tilt: 0.3, cx: c, cy: c, scale: 1)
        let rs = radiusScale(size, o.v("rsPow", 0.6))
        let orbitN = Int(o.v("orbitN", 12)), ghostN = Int(o.v("ghostN", 40)), particles = Int(o.v("particles", 3))
        var dots: [OrbDot] = []
        dots.reserveCapacity(orbitN * (ghostN + particles))
        for orb in 0..<orbitN {
            let h1 = hashD(Double(orb), 1.7), h2 = hashD(Double(orb), 5.2), h3 = hashD(Double(orb), 8.9)
            let ro = R * (0.45 + 0.52 * h1)
            let th = h1 * 2 * .pi
            let phi = acos(2 * h2 - 1)
            let nx = sin(phi) * cos(th), ny = cos(phi), nz = sin(phi) * sin(th)
            var ux = -ny, uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul; uy /= ul
            let vx = ny * uz - nz * uy, vy = nz * ux - nx * uz, vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
            func point(_ a: Double) -> (Double, Double, Double) {
                pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
            }
            for k in 0..<ghostN {
                let (px, py, z) = point(Double(k) / Double(ghostN) * 2 * .pi)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: o.v("ghostR", 0.9) * rs, white: 0.72, a: o.v("ghostA", 0.5) * (0.4 + 0.6 * depth)))
            }
            for m in 0..<particles {
                let (px, py, z) = point(t * speed + Double(m) / Double(particles) * 2 * .pi + h2 * 6)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: (o.v("partR", 1.2) + o.v("partRDepth", 1.6) * depth) * rs, white: 0.3 - 0.22 * depth))
            }
        }
        return dots
    }

    // MARK: Globe – searching

    static func globe(_ size: Double, _ t: Double, _ o: OrbPreset) -> [OrbDot] {
        let spin = 0.5
        let c = size / 2
        let radius = c * 0.82
        let pt = projector(yaw: t * spin, tilt: 0.4 + 0.06 * sin(t * 0.35), cx: c, cy: c, scale: radius)
        let scan = t * (spin + (1.7 - spin) * o.v("scanMul", 1))
        let rs = radiusScale(size, o.v("rsPow", 0.6))
        let dimBase = o.v("dimBase", 1)
        let latRings = Int(o.v("latRings", 17)), lonDensity = o.v("lonDensity", 44)
        var dots: [OrbDot] = []
        for li in 0...latRings {
            let lat = -Double.pi / 2 + Double(li) / Double(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon), sinLat, cosLat * sin(lon))
                let depth = (z + 1) / 2
                let d = angleDelta(lon + t * spin, scan)
                let boost = exp(-(d * d) / 0.18) * max(0, z)
                dots.append(OrbDot(x: px, y: py, z: z,
                                   r: (o.v("rBase", 0.6) + o.v("rDepth", 1.7) * depth + o.v("rBoost", 1) * boost) * rs,
                                   white: o.v("inkFar", 0.62) - o.v("inkSpan", 0.54) * depth,
                                   a: dimBase + (1 - dimBase) * min(1, boost)))
            }
        }
        return dots
    }

    // MARK: Wave – listening

    static func wave(_ size: Double, _ t: Double, _ o: OrbPreset) -> [OrbDot] {
        let c = size / 2
        let R = c * 0.874
        let pt = projector(yaw: t * 0.18, tilt: 0.38, cx: c, cy: c, scale: 1)
        let rs = radiusScale(size, o.v("rsPow", 0.6))
        let rings = Int(o.v("rings", 15)), lonDensity = o.v("lonDensity", 40)
        var dots: [OrbDot] = []
        for ri in 0...rings {
            let lat = -Double.pi / 2 + Double(ri) / Double(rings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
            let rr = R * (0.88 + 0.105 * w)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            let crest = max(0, w)
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * .pi
                let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / R + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z,
                                   r: (o.v("rBase", 0.6) + o.v("rDepth", 1.7) * depth) * (1 + 0.4 * crest) * rs,
                                   white: 0.66 - 0.56 * depth - 0.1 * crest))
            }
        }
        return dots
    }

    // MARK: Ring – breathing (ribbon painter, face-on)

    static func ring(_ size: Double, _ t: Double, _ o: OrbPreset) -> [OrbDot] {
        let c = size / 2
        let R = c * 0.78
        let spin = o.v("spin", 1)
        let camTilt = 0.3
        let pt = projector(yaw: t * 0.1 * spin, tilt: camTilt, cx: c, cy: c, scale: 1)
        let rs = radiusScale(size, o.v("rsPow", 0.6))
        let faceOn = o.v("faceOn", 0) != 0
        let ya = t * 0.24 * spin
        let ta = faceOn ? -camTilt : 0.55 + 0.3 * sin(t * 0.18) * spin
        let ux = cos(ya), uy = 0.0, uz = sin(ya)
        let vx = -uz * sin(ta), vy = cos(ta), vz = ux * sin(ta)
        let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx
        let wobMul = o.v("wobMul", 1)
        let baseR = faceOn ? R / (1 + 0.85 * 0.23 * wobMul) : R
        let lanes = Int(o.v("lanes", 5)), segs = Int(o.v("segs", 88))
        var dots: [OrbDot] = []
        dots.reserveCapacity(lanes * segs)
        for w in 0..<lanes {
            let mid = Double(lanes - 1) / 2
            let laneOff = (Double(w) - mid) * 0.075
            let edge = abs(Double(w) - mid) / max(1, mid)
            for k in 0..<segs {
                let a = Double(k) / Double(segs) * 2 * .pi
                let wob = (0.16 * sin(a * 3 - t * 1.7 + Double(w) * 0.22) + 0.07 * sin(a * 5 + t * 1.1)) * wobMul
                let radial = faceOn ? 1 + wob : 1
                let off = faceOn ? laneOff : laneOff + wob
                let x = ux * cos(a) + vx * sin(a) + nx * off
                let y = uy * cos(a) + vy * sin(a) + ny * off
                let z = uz * cos(a) + vz * sin(a) + nz * off
                let l = (x * x + y * y + z * z).squareRoot()
                let rr = baseR * radial
                let (px, py, zr) = pt(x / l * rr, y / l * rr, z / l * rr)
                let depth = (zr / R + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: zr,
                                   r: (o.v("rBase", 1.1) + o.v("rDepth", 1.7) * depth) * (1 - 0.25 * edge) * rs,
                                   white: 0.52 - 0.44 * depth + 0.18 * edge,
                                   a: 0.4 + 0.6 * depth))
            }
        }
        return dots
    }
}

/// The orb plus a short line – replaces spinners wherever the AI is busy.
struct FennThinking: View {
    var state: OrbState = .working
    var text: String? = nil
    var size: CGFloat = 18
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        HStack(spacing: 8) {
            ThinkingOrb(state: state, size: size)
            if let text {
                Text(text)
                    .font(.fenn(size: size <= 18 ? 12 : 14, weight: .medium))
                    .foregroundStyle(Fenn.fg.opacity(0.7))
                    .overlay {
                        // A soft highlight gliding over the words – subtle, and off with Reduce Motion.
                        if !reduceMotion {
                            GeometryReader { proxy in
                                LinearGradient(colors: [.clear, Fenn.peach.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: proxy.size.width * 0.4)
                                    .offset(x: shimmer ? proxy.size.width : -proxy.size.width * 0.4)
                            }
                            .mask(Text(text).font(.fenn(size: size <= 18 ? 12 : 14, weight: .medium)))
                            .allowsHitTesting(false)
                        }
                    }
                    .lineLimit(1)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { shimmer = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Slow ember aurora plus a faint dot grid – the living layer behind Fenn's glass.
/// Drifts over ~90 s so it is felt more than seen; frozen with Reduce Motion.
struct FennAurora: View {
    var intensity: Double = 1
    var grid = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 36_000)
                Canvas { g, size in
                    let blobs: [(Color, Double, Double, Double)] = [
                        (Fenn.accent, 0.20, 0.070, 0.0),
                        (Fenn.ember, 0.30, 0.050, 2.1),
                        (Fenn.amber, 0.09, 0.085, 4.2)
                    ]
                    let reach = max(size.width, size.height) * 0.6
                    for (color, alpha, speed, phase) in blobs {
                        let center = CGPoint(x: size.width * (0.5 + 0.4 * sin(t * speed + phase)),
                                             y: size.height * (0.22 + 0.18 * cos(t * speed * 0.8 + phase * 1.3)))
                        g.fill(Path(CGRect(origin: .zero, size: size)),
                               with: .radialGradient(Gradient(colors: [color.opacity(alpha * intensity), color.opacity(0)]),
                                                     center: center, startRadius: 0, endRadius: reach))
                    }
                }
            }
            if grid {
                Canvas { g, size in
                    let step: Double = 22
                    var y = step / 2
                    while y < size.height {
                        let fade = max(0, 1 - y / (size.height * 0.7))
                        if fade > 0 {
                            var x = step / 2
                            while x < size.width {
                                g.fill(Path(ellipseIn: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)),
                                       with: .color(Fenn.fg.opacity(0.07 * fade * intensity)))
                                x += step
                            }
                        }
                        y += step
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
