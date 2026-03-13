import Cocoa

let size = CGSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()

// Draw black background
NSColor.black.setFill()
NSRect(origin: .zero, size: size).fill()

// Draw white shield
if #available(macOS 11.0, *) {
    let config = NSImage.SymbolConfiguration(pointSize: 600, weight: .regular)
    if let shieldImage = NSImage(systemSymbolName: "shield", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        
        // Tint the symbol white
        let tintedShield = NSImage(size: shieldImage.size)
        tintedShield.lockFocus()
        shieldImage.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
        NSColor.white.set()
        NSRect(origin: .zero, size: shieldImage.size).fill(using: .sourceAtop)
        tintedShield.unlockFocus()
        
        let rect = NSRect(
            x: (size.width - shieldImage.size.width) / 2.0,
            y: (size.height - shieldImage.size.height) / 2.0,
            width: shieldImage.size.width,
            height: shieldImage.size.height
        )
        tintedShield.draw(in: rect)
    }
}

image.unlockFocus()

// Save to PNG
if let tiffData = image.tiffRepresentation,
   let bitmapImage = NSBitmapImageRep(data: tiffData),
   let pngData = bitmapImage.representation(using: .png, properties: [:]) {
    let url = URL(fileURLWithPath: "icon.png")
    try? pngData.write(to: url)
    print("Saved icon.png")
}
