import Foundation
import AVFoundation
import CryptoKit
let url = URL(fileURLWithPath:CommandLine.arguments[1]), output = URL(fileURLWithPath:CommandLine.arguments[2])
let seconds = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 600
let player = try AVAudioPlayer(contentsOf:url); player.numberOfLoops = -1; player.volume = 0.35
let start = Date(); var failures = 0, wraps = 0, last = 0.0
var rows = ["elapsed,currentTime,isPlaying"]
guard player.play() else { fatalError("Audio output failed to start") }
while Date().timeIntervalSince(start) < seconds {
    RunLoop.current.run(until:Date().addingTimeInterval(0.1))
    let current = player.currentTime
    if !player.isPlaying { failures += 1 }
    if current < last - 1 { wraps += 1 }
    rows.append("\(Date().timeIntervalSince(start)),\(current),\(player.isPlaying)"); last = current
}
player.stop(); let stopped = !player.isPlaying
try rows.joined(separator:"\n").write(to:output.appendingPathExtension("csv"),atomically:true,encoding:.utf8)
let report: [String:Any] = ["elapsedSeconds":Date().timeIntervalSince(start),"sourceDuration":player.duration,"loopsObserved":wraps,"notPlayingSamples":failures,"stopped":stopped,"playerCount":1,"sha256":SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined(),"limit":"Player state monitoring does not prove absence of acoustic clicks or perceived beat gaps; user listening still required."]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathExtension("json")); print(report)
