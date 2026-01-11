import UIKit
import CoreImage

public class RealisticMockImages {
    
    public static func generateStereoImages() -> (UIImage, UIImage) {
        // Generate two realistic test images
        let leftImage = createTestScene(offset: 0, camera: "Navigation")
        let rightImage = createTestScene(offset: 20, camera: "Imaging")
        
        return (leftImage, rightImage)
    }
    
    private static func createTestScene(offset: CGFloat, camera: String) -> UIImage {
        let size = CGSize(width: 800, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let ctx = context.cgContext
            
            // Draw realistic background (gradient sky)
            let skyColors = [
                UIColor(red: 0.5, green: 0.7, blue: 1.0, alpha: 1.0).cgColor,
                UIColor(red: 0.8, green: 0.9, blue: 1.0, alpha: 1.0).cgColor
            ]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: skyColors as CFArray,
                                        locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(gradient,
                                      start: CGPoint(x: size.width/2, y: 0),
                                      end: CGPoint(x: size.width/2, y: size.height/2),
                                      options: [])
            }
            
            // Draw ground
            ctx.setFillColor(UIColor(red: 0.4, green: 0.6, blue: 0.3, alpha: 1.0).cgColor)
            ctx.fill(CGRect(x: 0, y: size.height/2, width: size.width, height: size.height/2))
            
            // Draw 3D cubes (with parallax offset for stereo effect)
            drawCube(in: ctx, at: CGPoint(x: 200 + offset, y: 300), size: 100, color: .red)
            drawCube(in: ctx, at: CGPoint(x: 400 + offset * 0.5, y: 280), size: 80, color: .blue)
            drawCube(in: ctx, at: CGPoint(x: 600 + offset * 0.3, y: 320), size: 60, color: .green)
            
            // Draw trees
            for i in 0..<5 {
                let x = 100 + CGFloat(i) * 150 + offset * 0.2
                drawTree(in: ctx, at: CGPoint(x: x, y: size.height/2))
            }
            
            // Draw "person" shape
            drawPerson(in: ctx, at: CGPoint(x: 350 + offset, y: 380))
            
            // Add some text
            let textStyle = NSMutableParagraphStyle()
            textStyle.alignment = .center
            
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.white,
                .strokeColor: UIColor.black,
                .strokeWidth: -2.0,
                .paragraphStyle: textStyle
            ]
            
            let text = "\(camera) Camera - Test Scene"
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - textSize.width)/2, y: 20), withAttributes: attrs)
            
            // Add timestamp
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm:ss"
            let timestamp = "📸 \(timeFormatter.string(from: Date()))"
            let smallAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .foregroundColor: UIColor.black,
                .backgroundColor: UIColor.white.withAlphaComponent(0.8)
            ]
            timestamp.draw(at: CGPoint(x: 20, y: size.height - 40), withAttributes: smallAttrs)
        }
    }
    
    private static func drawCube(in ctx: CGContext, at center: CGPoint, size: CGFloat, color: UIColor) {
        // Front face
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - size/2, y: center.y - size/2, width: size, height: size))
        
        // Shadow
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.3).cgColor)
        ctx.fillEllipse(in: CGRect(x: center.x - size/3, y: center.y + size/2, width: size/1.5, height: size/4))
    }
    
    private static func drawTree(in ctx: CGContext, at base: CGPoint) {
        // Trunk
        ctx.setFillColor(UIColor.brown.cgColor)
        ctx.fill(CGRect(x: base.x - 10, y: base.y - 60, width: 20, height: 60))
        
        // Leaves (triangle)
        ctx.setFillColor(UIColor.green.cgColor)
        ctx.move(to: base)
        ctx.addLine(to: CGPoint(x: base.x - 40, y: base.y - 60))
        ctx.addLine(to: CGPoint(x: base.x + 40, y: base.y - 60))
        ctx.closePath()
        ctx.fillPath()
        
        ctx.move(to: CGPoint(x: base.x, y: base.y - 40))
        ctx.addLine(to: CGPoint(x: base.x - 30, y: base.y - 80))
        ctx.addLine(to: CGPoint(x: base.x + 30, y: base.y - 80))
        ctx.closePath()
        ctx.fillPath()
    }
    
    private static func drawPerson(in ctx: CGContext, at position: CGPoint) {
        // Head
        ctx.setFillColor(UIColor.systemPink.cgColor)
        ctx.fillEllipse(in: CGRect(x: position.x - 15, y: position.y - 60, width: 30, height: 30))
        
        // Body
        ctx.setFillColor(UIColor.systemBlue.cgColor)
        ctx.fill(CGRect(x: position.x - 20, y: position.y - 30, width: 40, height: 50))
        
        // Arms
        ctx.setStrokeColor(UIColor.systemBlue.cgColor)
        ctx.setLineWidth(8)
        ctx.move(to: CGPoint(x: position.x, y: position.y - 20))
        ctx.addLine(to: CGPoint(x: position.x - 30, y: position.y - 10))
        ctx.strokePath()
        
        ctx.move(to: CGPoint(x: position.x, y: position.y - 20))
        ctx.addLine(to: CGPoint(x: position.x + 30, y: position.y - 10))
        ctx.strokePath()
        
        // Legs
        ctx.setFillColor(UIColor.darkGray.cgColor)
        ctx.fill(CGRect(x: position.x - 15, y: position.y + 20, width: 12, height: 40))
        ctx.fill(CGRect(x: position.x + 3, y: position.y + 20, width: 12, height: 40))
    }
}
