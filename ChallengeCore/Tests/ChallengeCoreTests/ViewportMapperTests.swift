import Testing
@testable import ChallengeCore

@Suite("ViewportMapper — normalized pose point → on-screen point (aspect-fill)")
struct ViewportMapperTests {

    @Test("identity when image and view match")
    func identity() {
        let p = ViewportMapper.aspectFill(nx: 0.5, ny: 0.5, imageW: 100, imageH: 100, viewW: 100, viewH: 100)
        #expect(abs(p.x - 50) < 1e-9)
        #expect(abs(p.y - 50) < 1e-9)
    }

    @Test("flips y from bottom-left (Vision) to top-left (screen)")
    func flipsY() {
        // ny = 1 is the top of the image in Vision's bottom-left space.
        let top = ViewportMapper.aspectFill(nx: 0, ny: 1, imageW: 100, imageH: 100, viewW: 100, viewH: 100)
        let bottom = ViewportMapper.aspectFill(nx: 0, ny: 0, imageW: 100, imageH: 100, viewW: 100, viewH: 100)
        #expect(abs(top.y - 0) < 1e-9)
        #expect(abs(bottom.y - 100) < 1e-9)
    }

    @Test("crops the overflowing axis, keeping center aligned")
    func cropsTallImageInSquareView() {
        // 100x200 image, 100x100 view: scale = 1, vertical overflow of 100 split top/bottom.
        let center = ViewportMapper.aspectFill(nx: 0.5, ny: 0.5, imageW: 100, imageH: 200, viewW: 100, viewH: 100)
        #expect(abs(center.x - 50) < 1e-9)
        #expect(abs(center.y - 50) < 1e-9)
        // The image top (ny=1) lands above the view (negative y) — cropped, as expected.
        let top = ViewportMapper.aspectFill(nx: 0.5, ny: 1, imageW: 100, imageH: 200, viewW: 100, viewH: 100)
        #expect(top.y < 0)
    }

    @Test("portrait phone case scales to fill height and crops width")
    func portraitFill() {
        // 1080x1920 image in a 1080x2400 view: must scale up to cover height.
        let p = ViewportMapper.aspectFill(nx: 0.5, ny: 0.5, imageW: 1080, imageH: 1920, viewW: 1080, viewH: 2400)
        #expect(abs(p.x - 540) < 1e-6)   // horizontal center unchanged
        #expect(abs(p.y - 1200) < 1e-6)  // vertical center of the taller view
    }
}
