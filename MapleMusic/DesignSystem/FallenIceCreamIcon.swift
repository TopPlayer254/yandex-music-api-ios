import SwiftUI

/// Vector interpretation of the supplied fallen_ice_cream_cone reference.
/// No screenshot grid/background: scales and tints like the other app symbols.
struct FallenIceCreamIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 23, y: 18))
        p.addQuadCurve(to: CGPoint(x: 34, y: 14), control: CGPoint(x: 26, y: 9))
        p.addLine(to: CGPoint(x: 77, y: 56))
        p.addQuadCurve(to: CGPoint(x: 75, y: 64), control: CGPoint(x: 82, y: 61))
        p.addLine(to: CGPoint(x: 28, y: 82))
        p.addQuadCurve(to: CGPoint(x: 23, y: 77), control: CGPoint(x: 23, y: 84))
        p.closeSubpath()
        var spill = Path()
        spill.move(to: CGPoint(x: 33, y: 77))
        spill.addCurve(to: CGPoint(x: 39, y: 98), control1: CGPoint(x: 27, y: 92), control2: CGPoint(x: 29, y: 98))
        spill.addLine(to: CGPoint(x: 88, y: 98))
        spill.addCurve(to: CGPoint(x: 92, y: 82), control1: CGPoint(x: 99, y: 98), control2: CGPoint(x: 101, y: 88))
        spill.addQuadCurve(to: CGPoint(x: 75, y: 72), control: CGPoint(x: 84, y: 75))
        spill.move(to: CGPoint(x: 72, y: 64))
        spill.addCurve(to: CGPoint(x: 66, y: 84), control1: CGPoint(x: 78, y: 74), control2: CGPoint(x: 74, y: 81))
        p.addPath(spill.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)))
        p.addRoundedRect(in: CGRect(x: 47, y: 4, width: 8, height: 12), cornerSize: CGSize(width: 4, height: 4))
        p.addRoundedRect(in: CGRect(x: 71, y: 8, width: 8, height: 24), cornerSize: CGSize(width: 4, height: 4))
        p.addEllipse(in: CGRect(x: 87, y: 28, width: 8, height: 8))
        p.addEllipse(in: CGRect(x: 7, y: 94, width: 8, height: 8))
        let side = min(rect.width, rect.height)
        return p.applying(CGAffineTransform(scaleX: side / 110, y: side / 110))
            .applying(CGAffineTransform(translationX: rect.midX - side / 2, y: rect.midY - side / 2))
    }
}
