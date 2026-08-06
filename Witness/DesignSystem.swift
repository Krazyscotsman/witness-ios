import SwiftUI

// MARK: - Shared palette (locked threshold values).
enum WV {
    static let bgLeft  = Color(hex: 0xfaf7f0)   // entry (threshold/login) — locked
    static let bgRight = Color(hex: 0xf5f1e8)
    static let printInk = Color(hex: 0x3a2d1f)
    static let teal = Color(hue: 176.0/360.0, saturation: 0.90, brightness: 0.43)
    static let gold = Color(hue: 40.5/360.0,  saturation: 0.73, brightness: 0.82)
    static let card = Color(hex: 0xffffff)       // interior cards — white, for pop
    static let danger = Color(hex: 0xb3402f)     // muted brick red (delete)
    static let parchment = Color(hex: 0xf5f1e8)  // recipe parchment — the interior field
}

// MARK: - Compass mark (the 8-point logo), ported from the web mockup's SVG.
struct CompassPolygons: Shape {
    let polygons: [[CGPoint]]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let sx = rect.width / 100, sy = rect.height / 100
        for poly in polygons {
            guard let first = poly.first else { continue }
            p.move(to: CGPoint(x: rect.minX + first.x * sx, y: rect.minY + first.y * sy))
            for pt in poly.dropFirst() {
                p.addLine(to: CGPoint(x: rect.minX + pt.x * sx, y: rect.minY + pt.y * sy))
            }
            p.closeSubpath()
        }
        return p
    }
}

struct CompassMark: View {
    var color: Color = WT.gold
    var body: some View {
        ZStack {
            CompassPolygons(polygons: [
                [CGPoint(x: 22, y: 22), CGPoint(x: 53, y: 47), CGPoint(x: 78, y: 78), CGPoint(x: 47, y: 53)],
                [CGPoint(x: 78, y: 22), CGPoint(x: 53, y: 53), CGPoint(x: 22, y: 78), CGPoint(x: 47, y: 47)]
            ])
            .fill(color.opacity(0.55))
            CompassPolygons(polygons: [
                [CGPoint(x: 50, y: 6),  CGPoint(x: 57, y: 50), CGPoint(x: 50, y: 94), CGPoint(x: 43, y: 50)],
                [CGPoint(x: 6,  y: 50), CGPoint(x: 50, y: 43), CGPoint(x: 94, y: 50), CGPoint(x: 50, y: 57)]
            ])
            .fill(color)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Provider brand marks (native shapes; swap for official assets at wiring).
struct GoogleGIcon: View {
    var size: CGFloat = 18
    var body: some View {
        let lw = size * 0.22
        ZStack {
            Circle().trim(from: 0.04, to: 0.29).stroke(Color(hex: 0x34A853), style: StrokeStyle(lineWidth: lw)).padding(lw/2)
            Circle().trim(from: 0.29, to: 0.54).stroke(Color(hex: 0xFBBC05), style: StrokeStyle(lineWidth: lw)).padding(lw/2)
            Circle().trim(from: 0.54, to: 0.79).stroke(Color(hex: 0xEA4335), style: StrokeStyle(lineWidth: lw)).padding(lw/2)
            Circle().trim(from: 0.79, to: 0.95).stroke(Color(hex: 0x4285F4), style: StrokeStyle(lineWidth: lw)).padding(lw/2)
            Rectangle().fill(Color(hex: 0x4285F4))
                .frame(width: size * 0.30, height: lw)
                .offset(x: size * 0.17)
        }
        .frame(width: size, height: size)
    }
}

struct FacebookIcon: View {
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Color(hex: 0x1877F2))
            Text("f")
                .font(.system(size: size * 0.8, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .offset(y: size * 0.03)
        }
        .frame(width: size, height: size)
    }
}

struct MicrosoftIcon: View {
    var size: CGFloat = 18
    var body: some View {
        let s = (size - 2) / 2
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Rectangle().fill(Color(hex: 0xF25022)).frame(width: s, height: s)
                Rectangle().fill(Color(hex: 0x7FBA00)).frame(width: s, height: s)
            }
            HStack(spacing: 2) {
                Rectangle().fill(Color(hex: 0x00A4EF)).frame(width: s, height: s)
                Rectangle().fill(Color(hex: 0xFFB900)).frame(width: s, height: s)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Interior background: flat, even recipe parchment (edge to edge, like the site).
struct ParchmentBackground: View {
    var body: some View {
        WV.parchment.ignoresSafeArea()
    }
}

// MARK: - Entry background (threshold + login): locked parchment + the doorway printed in.
struct ParchmentDoorBackground: View {
    var fade: Double = 0.41
    var inkContrast: Double = 1.35

    var body: some View {
        ZStack {
            LinearGradient(colors: [WV.bgLeft, WV.bgRight], startPoint: .leading, endPoint: .trailing)
                .ignoresSafeArea()
            GeometryReader { geo in
                doorPrint(geo.size.width, geo.size.height)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
        }
    }

    private func doorPrint(_ w: CGFloat, _ h: CGFloat) -> some View {
        Rectangle()
            .fill(WV.printInk)
            .mask(
                Image("doorway")
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .grayscale(1)
                    .brightness(0.12)
                    .contrast(inkContrast)
                    .colorInvert()
                    .luminanceToAlpha()
            )
            .frame(width: w, height: h)
            .opacity(fade)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .black, location: 0.38)
                    ],
                    startPoint: .leading, endPoint: .trailing)
            )
            .offset(x: w * 0.22)
    }
}
