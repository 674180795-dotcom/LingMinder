import AppKit
import AVFoundation
import CryptoKit
let destination = URL(fileURLWithPath:CommandLine.arguments[1])
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
guard let original = Bundle(path:"/Applications/DeskMinder.app") else { fatalError("DeskMinder.app not found") }
var manifest: [[String:Any]] = []
for (name,ext) in [("ticking","m4a"),("heart-beat","m4a"),("binaural","m4a"),("relax-music","m4a"),("drag-sound","aiff"),("pong","aiff"),("funky","m4a"),("notification","mp3")] {
    guard let asset = NSDataAsset(name:name,bundle:original) else { fatalError("Missing asset: \(name)") }
    let url = destination.appendingPathComponent("\(name).\(ext)"); try asset.data.write(to:url)
    let file = try AVAudioFile(forReading:url)
    manifest.append(["name":name,"file":url.lastPathComponent,"sha256":SHA256.hash(data:asset.data).map{String(format:"%02x",$0)}.joined(),"bytes":asset.data.count,"duration":Double(file.length)/file.processingFormat.sampleRate,"sampleRate":file.processingFormat.sampleRate,"channels":file.processingFormat.channelCount])
}
let data = try JSONSerialization.data(withJSONObject:["source":"DeskMinder 2.0.9 installed on this Mac; personal-use audio reference","assets":manifest],options:[.prettyPrinted,.sortedKeys]); try data.write(to:destination.deletingLastPathComponent().appendingPathComponent("AudioManifest.json"))
