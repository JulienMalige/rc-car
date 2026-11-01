import Foundation

/// A camera frame's colour without its brightness: the interleaved Cb and Cr bytes of a 4:2:0 bi-planar image (ARKit's
/// captured image, plane 1), one pair per 2×2 block of pixels. Shadows and lamps change the brightness; the car's red
/// stays red.
public struct ChromaImage {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let base: UnsafePointer<UInt8>

    public init(width: Int, height: Int, bytesPerRow: Int, base: UnsafePointer<UInt8>) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.base = base
    }

    /// A point and a distance that can become pixel indices (finite, not absurdly far).
    static func usable(_ p: SIMD2<Double>, _ r: Double) -> Bool {
        p.x.isFinite && p.y.isFinite && r.isFinite && abs(p.x) < 100_000 && abs(p.y) < 100_000 && r >= 0 && r < 10_000
    }

    @inline(__always) func bin(_ x: Int, _ y: Int) -> Int {
        let i = y * bytesPerRow + 2 * x
        return ColorModel.bin(cb: base[i], cr: base[i + 1])
    }
}

/// How much each colour looks like the car rather than what is around it, learnt from one frame when the car is
/// tapped: the colours on the car against those of a ring of floor around it.
public struct ColorModel {
    /// Steps per channel: 32 × 32 (Cb, Cr) bins.
    public static let levels = 32
    /// The car's share of each bin, 0 (floor) to 1 (car).
    public private(set) var weights: [Float]

    @inline(__always) public static func bin(cb: UInt8, cr: UInt8) -> Int {
        Int(cb >> 3) * levels + Int(cr >> 3)
    }

    public init(weights: [Float]) {
        self.weights = weights
    }

    /// From the two histograms, each blurred over its neighbouring bins first (a lamp moves the colours a little).
    public init(car: [Float], ground: [Float]) {
        let c = ColorModel.blur(car)
        let g = ColorModel.blur(ground)
        let sc = max(c.reduce(0, +), 1e-6)
        let sg = max(g.reduce(0, +), 1e-6)
        weights = zip(c, g).map { pc, pg in
            let a = pc / sc
            let b = pg / sg
            return a / (a + b + 0.0005)
        }
    }

    /// Learns the colours within `radius` of `center` (the car; its middle counts more) against those of the ring
    /// `ring` around it (the floor). `keep` picks which colours inside count as the car: all of them for a first
    /// guess, then only those the first guess called car, so that the floor showing around the car's sides does not
    /// count as car. Chroma pixels.
    public static func learn(from image: ChromaImage, center: SIMD2<Double>, radius: Double, ring: ClosedRange<Double>,
                             keep: ((Int) -> Bool)? = nil) -> ColorModel {
        let count = levels * levels
        guard ChromaImage.usable(center, ring.upperBound), radius > 0 else {
            return ColorModel(weights: [Float](repeating: 0, count: count))
        }
        var car = [Float](repeating: 0, count: count)
        var ground = [Float](repeating: 0, count: count)
        let outer = ring.upperBound
        let x0 = max(0, Int(center.x - outer)), x1 = min(image.width - 1, Int(center.x + outer))
        let y0 = max(0, Int(center.y - outer)), y1 = min(image.height - 1, Int(center.y + outer))
        guard x0 <= x1, y0 <= y1 else { return ColorModel(weights: [Float](repeating: 0, count: count)) }
        let r2 = radius * radius
        let inner2 = ring.lowerBound * ring.lowerBound
        let outer2 = outer * outer
        for y in y0...y1 {
            let dy = Double(y) - center.y
            for x in x0...x1 {
                let dx = Double(x) - center.x
                let d2 = dx * dx + dy * dy
                let bin = image.bin(x, y)
                if d2 <= r2 {
                    if keep?(bin) ?? true { car[bin] += Float(1 - 0.5 * d2 / r2) }
                } else if d2 >= inner2 && d2 <= outer2 {
                    ground[bin] += 1
                }
            }
        }
        return ColorModel(car: car, ground: ground)
    }

    static func blur(_ h: [Float]) -> [Float] {
        let n = levels
        var out = [Float](repeating: 0, count: h.count)
        for i in 0..<n {
            for j in 0..<n {
                var s: Float = 0
                for di in -1...1 {
                    for dj in -1...1 {
                        let a = i + di, b = j + dj
                        guard a >= 0, a < n, b >= 0, b < n else { continue }
                        let k: Float = di == 0 && dj == 0 ? 4 : (di == 0 || dj == 0 ? 2 : 1)
                        s += h[a * n + b] * k
                    }
                }
                out[i * n + j] = s / 16
            }
        }
        return out
    }
}

/// Where the car is in one frame: the middle of its colour, the direction of its length, how much of it showed.
public struct BlobFix: Equatable {
    /// Chroma pixels.
    public var center: SIMD2<Double>
    /// The blob's long axis, radians from the image's x axis (a line: the same as + pi).
    public var axis: Double
    /// Long over short side, 1 for a round blob.
    public var elongation: Double
    /// The car-likeness summed over the blob's pixels.
    public var mass: Double
}

/// Follows the car from frame to frame by its colour: mean shift from where it should be, then the blob's moments for
/// its middle and its axis.
public struct BlobTracker {
    public var model: ColorModel
    /// Pixels less car-like than this are left out: the floor's colours pull nothing.
    public var threshold: Float = 0.5

    public init(model: ColorModel) {
        self.model = model
    }

    /// Locks on the car where it was tapped (chroma pixels; `carLength`: how long the car should look there): a first
    /// guess of its colours, the blob they make, then the colours of that blob alone against the floor around it.
    /// nil when the spot does not stand out from the floor (a tap beside the car, or on the bare floor).
    public static func lock(_ image: ChromaImage, at tap: SIMD2<Double>, carLength: Double) -> (tracker: BlobTracker, fix: BlobFix)? {
        guard carLength > 2 else { return nil }
        let ring = (0.9 * carLength)...(1.6 * carLength)
        let first = ColorModel.learn(from: image, center: tap, radius: 0.35 * carLength, ring: ring)
        guard let rough = BlobTracker(model: first).track(image, from: tap, radius: 0.6 * carLength) else { return nil }
        let refined = ColorModel.learn(from: image, center: rough.center, radius: 0.6 * carLength, ring: ring,
                                       keep: { first.weights[$0] > 0.5 })
        let tracker = BlobTracker(model: refined)
        guard let fix = tracker.track(image, from: rough.center, radius: 0.6 * carLength) else { return nil }
        let contrast = tracker.contrast(image, center: fix.center, radius: 0.3 * carLength, ring: ring)
        guard contrast.inside > 0.5, contrast.outside < 0.15 else { return nil }
        return (tracker, fix)
    }

    /// From `start`, moves to the middle of the car-coloured pixels within `radius` until it settles; nil when nothing
    /// car-coloured is there.
    public func track(_ image: ChromaImage, from start: SIMD2<Double>, radius: Double, iterations: Int = 8) -> BlobFix? {
        guard ChromaImage.usable(start, radius) else { return nil }
        var center = start
        for _ in 0..<iterations {
            guard let m = moments(image, at: center, radius: radius) else { return nil }
            let shift = m.mean - center
            center = m.mean
            if (shift.x * shift.x + shift.y * shift.y) < 0.09 { break }
        }
        guard let m = moments(image, at: center, radius: radius) else { return nil }
        let half = (m.xx + m.yy) / 2
        let spread = (((m.xx - m.yy) / 2) * ((m.xx - m.yy) / 2) + m.xy * m.xy).squareRoot()
        let long = half + spread
        let short = max(half - spread, 1e-6)
        return BlobFix(center: m.mean, axis: 0.5 * atan2(2 * m.xy, m.xx - m.yy), elongation: (long / short).squareRoot(), mass: m.mass)
    }

    /// The most car-coloured spot within `reach` of `center` (or of the whole frame), on a coarse grid of `step`
    /// pixels, summed over a square about the car's size: where to start following again after losing the car.
    public func search(_ image: ChromaImage, around center: SIMD2<Double>? = nil, reach: Double? = nil, radius: Double,
                       step: Int = 4) -> (point: SIMD2<Double>, mass: Double)? {
        var x0 = 0, x1 = image.width - 1, y0 = 0, y1 = image.height - 1
        guard radius.isFinite, radius > 0 else { return nil }
        if let center, let reach {
            guard ChromaImage.usable(center, reach) else { return nil }
            x0 = max(0, Int(center.x - reach)); x1 = min(image.width - 1, Int(center.x + reach))
            y0 = max(0, Int(center.y - reach)); y1 = min(image.height - 1, Int(center.y + reach))
        }
        guard step > 0, x0 < x1, y0 < y1 else { return nil }
        let cols = (x1 - x0) / step + 1
        let rows = (y1 - y0) / step + 1
        // an integral image of the car-likeness on the grid
        var sums = [Double](repeating: 0, count: (cols + 1) * (rows + 1))
        for r in 0..<rows {
            var line = 0.0
            for c in 0..<cols {
                let w = model.weights[image.bin(x0 + c * step, y0 + r * step)]
                if w > threshold { line += Double(w - threshold) / Double(1 - threshold) }
                sums[(r + 1) * (cols + 1) + c + 1] = sums[r * (cols + 1) + c + 1] + line
            }
        }
        let k = max(1, Int(radius / Double(step)))
        var best = 0.0
        var spot: (Int, Int)?
        for r in 0..<rows {
            for c in 0..<cols {
                let ra = max(0, r - k), rb = min(rows, r + k + 1)
                let ca = max(0, c - k), cb = min(cols, c + k + 1)
                let s = sums[rb * (cols + 1) + cb] - sums[ra * (cols + 1) + cb] - sums[rb * (cols + 1) + ca] + sums[ra * (cols + 1) + ca]
                if s > best {
                    best = s
                    spot = (c, r)
                }
            }
        }
        guard let spot else { return nil }
        return (SIMD2(Double(x0 + spot.0 * step), Double(y0 + spot.1 * step)), best * Double(step * step))
    }

    /// The mean car-likeness inside `radius` and in the ring of floor around it: a tap on the car gives a high first
    /// figure and a low second one, a tap on the floor two alike.
    public func contrast(_ image: ChromaImage, center: SIMD2<Double>, radius: Double,
                         ring: ClosedRange<Double>) -> (inside: Double, outside: Double) {
        guard ChromaImage.usable(center, ring.upperBound) else { return (0, 0) }
        let outer = ring.upperBound
        let x0 = max(0, Int(center.x - outer)), x1 = min(image.width - 1, Int(center.x + outer))
        let y0 = max(0, Int(center.y - outer)), y1 = min(image.height - 1, Int(center.y + outer))
        guard x0 <= x1, y0 <= y1 else { return (0, 0) }
        let r2 = radius * radius, inner2 = ring.lowerBound * ring.lowerBound, outer2 = outer * outer
        var si = 0.0, ni = 0.0, so = 0.0, no = 0.0
        for y in y0...y1 {
            let dy = Double(y) - center.y
            for x in x0...x1 {
                let dx = Double(x) - center.x
                let d2 = dx * dx + dy * dy
                let w = Double(model.weights[image.bin(x, y)])
                if d2 <= r2 {
                    si += w
                    ni += 1
                } else if d2 >= inner2 && d2 <= outer2 {
                    so += w
                    no += 1
                }
            }
        }
        return (ni > 0 ? si / ni : 0, no > 0 ? so / no : 0)
    }

    struct Moments {
        var mass: Double
        var mean: SIMD2<Double>
        var xx: Double
        var yy: Double
        var xy: Double
    }

    func moments(_ image: ChromaImage, at c: SIMD2<Double>, radius: Double) -> Moments? {
        let x0 = max(0, Int((c.x - radius).rounded(.down))), x1 = min(image.width - 1, Int((c.x + radius).rounded(.up)))
        let y0 = max(0, Int((c.y - radius).rounded(.down))), y1 = min(image.height - 1, Int((c.y + radius).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return nil }
        let r2 = radius * radius
        let span = Double(1 - threshold)
        var m = 0.0, sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
        for y in y0...y1 {
            let dy = Double(y) - c.y
            for x in x0...x1 {
                let dx = Double(x) - c.x
                guard dx * dx + dy * dy <= r2 else { continue }
                let w = model.weights[image.bin(x, y)]
                guard w > threshold else { continue }
                let ww = Double(w - threshold) / span
                m += ww
                sx += ww * dx
                sy += ww * dy
                sxx += ww * dx * dx
                syy += ww * dy * dy
                sxy += ww * dx * dy
            }
        }
        guard m > 0.5 else { return nil }
        let mx = sx / m, my = sy / m
        return Moments(mass: m, mean: SIMD2(c.x + mx, c.y + my), xx: sxx / m - mx * mx, yy: syy / m - my * my,
                       xy: sxy / m - mx * my)
    }
}
