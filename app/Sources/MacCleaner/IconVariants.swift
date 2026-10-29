import SwiftUI

enum LeviIconVariant: String, CaseIterable {
    case a, b, c

    var label: String {
        switch self {
        case .a: "A · Jabot"
        case .b: "B · Spotless"
        case .c: "C · Captain's crest"
        }
    }

    var background: Color {
        switch self {
        case .a: Color(red: 0.035, green: 0.10, blue: 0.22)
        case .b: Color(red: 0.055, green: 0.26, blue: 0.20)
        case .c: Color(red: 0.34, green: 0.07, blue: 0.13)
        }
    }
}

/// Original illustrated objects in AppIcon's 824-in-1024 tile.
struct IconVariantView: View {
    var variant: LeviIconVariant
    var size: CGFloat = 1024

    private let shade = Color(red: 0.45, green: 0.59, blue: 0.62)
    private let base = Color(red: 0.84, green: 0.90, blue: 0.88)
    private let cream = Color(red: 1, green: 0.97, blue: 0.85)
    private let brass = Color(red: 0.62, green: 0.43, blue: 0.19)

    private var tileColors: [Color] {
        switch variant {
        case .a: [variant.background, Color(red: 0.045, green: 0.33, blue: 0.35)]
        case .b: [variant.background, Color(red: 0.04, green: 0.06, blue: 0.07)]
        case .c: [variant.background, Color(red: 0.05, green: 0.03, blue: 0.055)]
        }
    }

    private var linen: LinearGradient {
        LinearGradient(colors: [.white, base, shade], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var metal: LinearGradient {
        LinearGradient(stops: [.init(color: cream, location: 0),
                              .init(color: Color(red: 0.86, green: 0.70, blue: 0.41), location: 0.25),
                              .init(color: brass, location: 0.53),
                              .init(color: cream, location: 0.73),
                              .init(color: brass, location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 224, style: .continuous)
                .fill(LinearGradient(colors: tileColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 224, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.13), .clear],
                                             center: .topLeading, startRadius: 0, endRadius: 850))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 224, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.40), .white.opacity(0.06), .black.opacity(0.2)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 3)
                }
                .frame(width: 824, height: 824)
            Ellipse().fill(.black.opacity(0.35)).frame(width: 390, height: 42)
                .blur(radius: 22).position(x: 520, y: 795)
            switch variant {
            case .a: jabot
            case .b: spotless
            case .c: crest
            }
        }
        .frame(width: 1024, height: 1024)
        .scaleEffect(size / 1024)
        .frame(width: size, height: size)
    }

    // A: four sculpted flounces, drawn from the bottom up.
    private var jabot: some View {
        ZStack {
            collar.fill(linen).shadow(color: .black.opacity(0.35), radius: 14, x: 7, y: 16)
            collar.stroke(.white.opacity(0.7), lineWidth: 3)
            Path { p in
                p.move(to: CGPoint(x: 286, y: 293))
                p.addLines([CGPoint(x: 423, y: 395), CGPoint(x: 481, y: 295)])
                p.move(to: CGPoint(x: 738, y: 293))
                p.addLines([CGPoint(x: 601, y: 395), CGPoint(x: 543, y: 295)])
            }.stroke(shade.opacity(0.6), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            flounce(top: 575, bottom: 788, width: 153)
            flounce(top: 480, bottom: 680, width: 182)
            flounce(top: 389, bottom: 570, width: 205)
            flounce(top: 316, bottom: 460, width: 184)
            brooch
            glint(x: 741, y: 427, radius: 40)
            glint(x: 305, y: 658, radius: 20).opacity(0.75)
        }
    }

    private var collar: Path {
        Path { p in
            p.move(to: CGPoint(x: 286, y: 273))
            p.addQuadCurve(to: CGPoint(x: 512, y: 235), control: CGPoint(x: 391, y: 212))
            p.addQuadCurve(to: CGPoint(x: 738, y: 273), control: CGPoint(x: 633, y: 212))
            p.addLines([CGPoint(x: 696, y: 385), CGPoint(x: 600, y: 417),
                        CGPoint(x: 540, y: 313), CGPoint(x: 484, y: 313),
                        CGPoint(x: 424, y: 417), CGPoint(x: 328, y: 385)])
            p.closeSubpath()
        }
    }

    private func flounce(top: CGFloat, bottom: CGFloat, width: CGFloat) -> some View {
        let fold = Path { p in
            p.move(to: CGPoint(x: 470, y: top))
            p.addQuadCurve(to: CGPoint(x: 512 - width, y: bottom - 40), control: CGPoint(x: 411, y: top + 57))
            p.addCurve(to: CGPoint(x: 512 + width, y: bottom - 40),
                       control1: CGPoint(x: 446, y: bottom + 30), control2: CGPoint(x: 566, y: bottom + 30))
            p.addQuadCurve(to: CGPoint(x: 554, y: top), control: CGPoint(x: 613, y: top + 57))
            p.closeSubpath()
        }
        return ZStack {
            fold.fill(linen).shadow(color: .black.opacity(0.30), radius: 7, x: 3, y: 12)
            ForEach(0..<5) { index in
                let d = CGFloat(index - 2)
                Path { p in
                    p.move(to: CGPoint(x: 512 + d * 13, y: top + 9))
                    p.addQuadCurve(to: CGPoint(x: 512 + d * width * 0.37, y: bottom - 7),
                                   control: CGPoint(x: 512 + d * 38, y: top + 74))
                    p.addLine(to: CGPoint(x: 530 + d * width * 0.37, y: bottom - 13))
                    p.closeSubpath()
                }.fill(LinearGradient(colors: [.white.opacity(0.08), shade.opacity(0.65), .white.opacity(0.65)],
                                      startPoint: .leading, endPoint: .trailing))
            }.clipShape(fold)
            Path { p in
                p.move(to: CGPoint(x: 518 - width, y: bottom - 40))
                p.addCurve(to: CGPoint(x: 506 + width, y: bottom - 40),
                           control1: CGPoint(x: 448, y: bottom + 22), control2: CGPoint(x: 566, y: bottom + 22))
            }.stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    private var brooch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 27).fill(metal).frame(width: 92, height: 106)
            RoundedRectangle(cornerRadius: 19)
                .fill(LinearGradient(colors: [Color(red: 0.23, green: 0.86, blue: 0.64),
                                              Color(red: 0.015, green: 0.37, blue: 0.27),
                                              Color(red: 0.005, green: 0.15, blue: 0.14)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 88)
            Path { p in
                p.move(to: CGPoint(x: 9, y: 15))
                p.addLines([CGPoint(x: 59, y: 12), CGPoint(x: 22, y: 62)])
                p.closeSubpath()
            }.fill(.white.opacity(0.25)).frame(width: 74, height: 88)
        }
        .frame(width: 92, height: 106)
        .shadow(color: .black.opacity(0.45), radius: 8, y: 8)
        .position(x: 512, y: 327)
        .overlay { glint(x: 491, y: 297, radius: 19) }
    }

    // B: the half-moon wipe reveals a dark mirror beneath a dull surface.
    private var spotless: some View {
        ZStack {
            disc
            cloth.rotationEffect(.degrees(-12)).offset(x: -24, y: 24)
                .shadow(color: .black.opacity(0.45), radius: 12, x: 8, y: 17)
            bubble(x: 730, y: 640, radius: 29)
            bubble(x: 768, y: 563, radius: 17)
            bubble(x: 302, y: 350, radius: 21)
            glint(x: 656, y: 306, radius: 61)
        }
    }

    private var disc: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [.white.opacity(0.8), shade, .black, shade],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().inset(by: 9)
                .fill(LinearGradient(colors: [Color(red: 0.28, green: 0.35, blue: 0.35),
                                              Color(red: 0.13, green: 0.18, blue: 0.19)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Path { p in
                p.move(to: CGPoint(x: 302, y: 39))
                p.addCurve(to: CGPoint(x: 309, y: 530),
                           control1: CGPoint(x: 124, y: 187), control2: CGPoint(x: 152, y: 430))
                p.addCurve(to: CGPoint(x: 302, y: 39),
                           control1: CGPoint(x: 631, y: 462), control2: CGPoint(x: 596, y: 97))
                p.closeSubpath()
            }.fill(LinearGradient(stops: [.init(color: .white.opacity(0.86), location: 0),
                                          .init(color: Color(red: 0.32, green: 0.60, blue: 0.59), location: 0.22),
                                          .init(color: Color(red: 0.015, green: 0.07, blue: 0.10), location: 0.47),
                                          .init(color: Color(red: 0.035, green: 0.15, blue: 0.18), location: 0.76),
                                          .init(color: base, location: 1)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            Path { p in
                p.move(to: CGPoint(x: 302, y: 39))
                p.addCurve(to: CGPoint(x: 309, y: 530),
                           control1: CGPoint(x: 124, y: 187), control2: CGPoint(x: 152, y: 430))
            }.stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Circle().inset(by: 16).trim(from: 0.53, to: 0.83)
                .stroke(.white.opacity(0.48), lineWidth: 3)
        }
        .frame(width: 552, height: 552).position(x: 520, y: 494)
        .shadow(color: .black.opacity(0.4), radius: 19, x: 10, y: 20)
    }

    private var cloth: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 31)
                .fill(LinearGradient(colors: [base, shade], startPoint: .top, endPoint: .bottom))
                .frame(width: 416, height: 170).position(x: 480, y: 663)
            Path { p in
                p.move(to: CGPoint(x: 278, y: 562))
                p.addQuadCurve(to: CGPoint(x: 303, y: 540), control: CGPoint(x: 280, y: 540))
                p.addLine(to: CGPoint(x: 635, y: 540))
                p.addQuadCurve(to: CGPoint(x: 664, y: 558), control: CGPoint(x: 661, y: 540))
                p.addLines([CGPoint(x: 713, y: 670), CGPoint(x: 350, y: 683)])
                p.addQuadCurve(to: CGPoint(x: 278, y: 650), control: CGPoint(x: 277, y: 691))
                p.closeSubpath()
            }.fill(linen)
            Path { p in
                p.move(to: CGPoint(x: 293, y: 653))
                p.addQuadCurve(to: CGPoint(x: 352, y: 672), control: CGPoint(x: 308, y: 678))
                p.addLine(to: CGPoint(x: 697, y: 660))
                p.move(to: CGPoint(x: 303, y: 716))
                p.addQuadCurve(to: CGPoint(x: 361, y: 730), control: CGPoint(x: 316, y: 736))
                p.addLine(to: CGPoint(x: 664, y: 730))
            }.stroke(.white.opacity(0.78), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 344, y: 556))
                p.addQuadCurve(to: CGPoint(x: 390, y: 661), control: CGPoint(x: 350, y: 610))
            }.stroke(shade.opacity(0.65), lineWidth: 9)
            Path { p in
                p.move(to: CGPoint(x: 375, y: 555))
                p.addLine(to: CGPoint(x: 413, y: 658))
            }.stroke(.white.opacity(0.75), lineWidth: 4)
            Path { p in
                p.move(to: CGPoint(x: 323, y: 699))
                p.addLine(to: CGPoint(x: 659, y: 699))
            }.stroke(shade.opacity(0.55), style: StrokeStyle(lineWidth: 3, dash: [5, 7]))
        }.frame(width: 1024, height: 1024)
    }

    private func bubble(x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
        Circle().fill(RadialGradient(colors: [.white.opacity(0.02), .white.opacity(0.17)],
                                      center: .topLeading, startRadius: 0, endRadius: radius * 2))
            .overlay {
                Circle().stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.08), .white.opacity(0.45)],
                                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 3)
            }
            .overlay(alignment: .topLeading) {
                Capsule().fill(.white.opacity(0.85)).frame(width: radius * 0.6, height: 4)
                    .rotationEffect(.degrees(-38)).offset(x: radius * 0.3, y: radius * 0.4)
            }
            .frame(width: radius * 2, height: radius * 2).position(x: x, y: y)
    }

    // C: an original domestic crest with brushed metal and crossed cleaning tools.
    private var crest: some View {
        ZStack {
            shield.fill(metal).shadow(color: .black.opacity(0.5), radius: 19, x: 8, y: 18)
            shield.stroke(LinearGradient(colors: [cream, brass.opacity(0.5)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 4)
            shield.fill(LinearGradient(colors: [cream, Color(red: 0.85, green: 0.80, blue: 0.63),
                                                Color(red: 0.60, green: 0.55, blue: 0.39)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                .scaleEffect(x: 0.88, y: 0.89)
            ForEach(0..<38) { index in
                Path { p in
                    let y = 285 + CGFloat(index) * 12
                    p.move(to: CGPoint(x: 275, y: y))
                    p.addLine(to: CGPoint(x: 749, y: y - 2))
                }.stroke(.white.opacity(index.isMultiple(of: 3) ? 0.16 : 0.065), lineWidth: 1)
            }.clipShape(shield)
            shield.stroke(brass.opacity(0.65), lineWidth: 3).scaleEffect(x: 0.84, y: 0.85)
            crestCloth.rotationEffect(.degrees(39))
                .shadow(color: .black.opacity(0.28), radius: 7, x: 4, y: 7)
            broom.rotationEffect(.degrees(-39))
                .shadow(color: .black.opacity(0.30), radius: 6, x: 4, y: 6)
            star.fill(metal).frame(width: 81, height: 81).position(x: 512, y: 335)
                .shadow(color: brass.opacity(0.65), radius: 3, y: 4)
            glint(x: 305, y: 304, radius: 27)
        }
    }

    private var shield: Path {
        Path { p in
            p.move(to: CGPoint(x: 512, y: 224))
            p.addCurve(to: CGPoint(x: 754, y: 283), control1: CGPoint(x: 610, y: 274), control2: CGPoint(x: 680, y: 282))
            p.addLine(to: CGPoint(x: 737, y: 530))
            p.addCurve(to: CGPoint(x: 512, y: 800), control1: CGPoint(x: 731, y: 673), control2: CGPoint(x: 621, y: 750))
            p.addCurve(to: CGPoint(x: 287, y: 530), control1: CGPoint(x: 403, y: 750), control2: CGPoint(x: 293, y: 673))
            p.addLine(to: CGPoint(x: 270, y: 283))
            p.addCurve(to: CGPoint(x: 512, y: 224), control1: CGPoint(x: 344, y: 282), control2: CGPoint(x: 414, y: 274))
            p.closeSubpath()
        }
    }

    private var crestCloth: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(linen).frame(width: 156, height: 252).position(x: 512, y: 534)
            RoundedRectangle(cornerRadius: 13).fill(linen).frame(width: 156, height: 66)
                .shadow(color: shade.opacity(0.7), radius: 4, y: 6).position(x: 512, y: 449)
            Path { p in
                p.move(to: CGPoint(x: 449, y: 641))
                p.addLines([CGPoint(x: 575, y: 641), CGPoint(x: 575, y: 487)])
                p.move(to: CGPoint(x: 456, y: 488))
                p.addLine(to: CGPoint(x: 456, y: 629))
            }.stroke(shade.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            Path { p in
                p.move(to: CGPoint(x: 447, y: 424))
                p.addLine(to: CGPoint(x: 574, y: 424))
            }.stroke(.white.opacity(0.9), lineWidth: 4)
        }.frame(width: 1024, height: 1024)
    }

    private var broom: some View {
        ZStack {
            Capsule().fill(metal).frame(width: 25, height: 254).position(x: 512, y: 467)
            Capsule().fill(cream.opacity(0.65)).frame(width: 4, height: 224).position(x: 505, y: 461)
            Path { p in
                p.move(to: CGPoint(x: 474, y: 567))
                p.addLines([CGPoint(x: 550, y: 567), CGPoint(x: 596, y: 695)])
                p.addQuadCurve(to: CGPoint(x: 428, y: 695), control: CGPoint(x: 512, y: 719))
                p.closeSubpath()
            }.fill(LinearGradient(colors: [cream, Color(red: 0.78, green: 0.59, blue: 0.28), brass],
                                  startPoint: .leading, endPoint: .trailing))
            ForEach(0..<9) { index in
                Path { p in
                    let d = CGFloat(index - 4)
                    p.move(to: CGPoint(x: 512 + d * 8, y: 594))
                    p.addLine(to: CGPoint(x: 512 + d * 18, y: 695))
                }.stroke(brass.opacity(0.75), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            RoundedRectangle(cornerRadius: 7)
                .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.39, blue: 0.35),
                                              Color(red: 0.09, green: 0.18, blue: 0.17)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 93, height: 31).position(x: 512, y: 579)
            Capsule().fill(cream.opacity(0.6)).frame(width: 77, height: 3).position(x: 512, y: 569)
        }.frame(width: 1024, height: 1024)
    }

    private var star: Path {
        Path { p in
            for index in 0..<10 {
                let angle = Double(index) * .pi / 5 - .pi / 2
                let radius = index.isMultiple(of: 2) ? 40.0 : 18.0
                let point = CGPoint(x: 40 + cos(angle) * radius, y: 40 + sin(angle) * radius)
                if index == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
            p.closeSubpath()
        }
    }

    private func glint(x: CGFloat, y: CGFloat, radius: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: x, y: y - radius))
            p.addQuadCurve(to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x + 7, y: y - 7))
            p.addQuadCurve(to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x + 7, y: y + 7))
            p.addQuadCurve(to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x - 7, y: y + 7))
            p.addQuadCurve(to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x - 7, y: y - 7))
            p.closeSubpath()
        }.fill(.white).shadow(color: .white.opacity(0.4), radius: 8)
    }
}

struct IconContactSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Captain Levi").font(.system(size: 40, weight: .bold))
            ForEach(LeviIconVariant.allCases, id: \.self) { variant in
                HStack(spacing: 72) {
                    IconVariantView(variant: variant, size: 384)
                    VStack(alignment: .leading, spacing: 28) {
                        Text(variant.label).font(.system(size: 26, weight: .semibold))
                        HStack(alignment: .bottom, spacing: 64) {
                            sample(variant, size: 128)
                            sample(variant, size: 32)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.04)))
            }
            Spacer(minLength: 0)
        }
        .padding(64)
        .frame(width: 1600, height: 1600, alignment: .topLeading)
        .background(Color(red: 0.10, green: 0.12, blue: 0.13))
        .foregroundStyle(.white)
    }

    private func sample(_ variant: LeviIconVariant, size: CGFloat) -> some View {
        VStack(spacing: 12) {
            IconVariantView(variant: variant, size: size)
            Text("\(Int(size)) px").font(.system(size: 18)).foregroundStyle(.secondary)
        }
    }
}
