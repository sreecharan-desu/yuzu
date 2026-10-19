// Usage: yuzuctl <cmd> [key=value ...]   e.g. yuzuctl preview kind=convert hover=2 duration=6
import Foundation
var info: [String: String] = [:]
let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else { print("usage: yuzuctl <preview|menu|settings|convert|quit> [k=v...]"); exit(1) }
info["cmd"] = cmd
for a in args.dropFirst() {
    let parts = a.split(separator: "=", maxSplits: 1).map(String.init)
    if parts.count == 2 { info[parts[0]] = parts[1] }
}
DistributedNotificationCenter.default().postNotificationName(.init("com.sreecharan.yuzu.debug"), object: nil,
                                                              userInfo: info, deliverImmediately: true)
RunLoop.main.run(until: Date().addingTimeInterval(0.2))
