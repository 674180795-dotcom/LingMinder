import AppKit
// Format conversion only: preserve the supplied artwork and its complete composition.
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let source = URL(fileURLWithPath:CommandLine.arguments[2])
guard let artwork = NSImage(contentsOf:source) else { fatalError("Cannot read icon artwork") }
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
func render(_ image: NSImage, _ pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in:NSRect(x:0,y:0,width:pixels,height:pixels),from:.zero,operation:.copy,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:url)
}
for size in [16,32,128,256,512] { for factor in [1,2] {
    try render(artwork,size*factor,to:root.appendingPathComponent("icon_\(size)x\(size)\(factor == 2 ? "@2x" : "").png"))
} }
guard let statusArtwork = NSImage(contentsOf:URL(fileURLWithPath:CommandLine.arguments[4])) else { fatalError("Cannot read status artwork") }
try render(statusArtwork,36,to:URL(fileURLWithPath:CommandLine.arguments[3]))
let statusBitmap = NSBitmapImageRep(data:try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))!
guard statusBitmap.hasAlpha, statusBitmap.colorAt(x:0,y:0)!.alphaComponent == 0 else { fatalError("Status icon must preserve transparent corners") }
print("Status icon: transparent background preserved")
