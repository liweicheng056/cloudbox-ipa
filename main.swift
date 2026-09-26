import UIKit

let argv = UnsafeMutableRawPointer(CommandLine.unsafeArgv)
    .bindMemory(to: UnsafeMutablePointer<CChar>?.self, capacity: Int(CommandLine.argc))
UIApplicationMain(CommandLine.argc, argv, nil, NSStringFromClass(AppDelegate.self))
