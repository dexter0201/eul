//
//  NetworkTopStore.swift
//  eul
//
//  Created by Gao Sun on 2020/10/17.
//  Copyright © 2020 Gao Sun. All rights reserved.
//

import AppKit
import SwiftUI

class NetworkTopStore: ObservableObject {
    struct NetworkSpeed: CustomStringConvertible {
        var inSpeedInByte: Double = 0
        var outSpeedInByte: Double = 0

        var totalSpeedInByte: Double {
            inSpeedInByte + outSpeedInByte
        }

        var description: String {
            fatalError("not implemented")
        }
    }

    struct ProcessNetworkUsage: ProcessUsage {
        typealias T = NetworkSpeed
        let pid: Int
        let command: String
        let value: NetworkSpeed
        let runningApp: NSRunningApplication?
    }

    static let shared = NetworkTopStore()

    private var lastTimestamp: TimeInterval
    private var lastInBytes: [Int: Double] = [:]
    private var lastOutBytes: [Int: Double] = [:]
    @ObservedObject var preferenceStore = PreferenceStore.shared
    @Published var processes: [ProcessNetworkUsage] = []

    var totalSpeed: NetworkSpeed {
        processes.reduce(into: NetworkSpeed()) { result, usage in
            result.inSpeedInByte += usage.value.inSpeedInByte
            result.outSpeedInByte += usage.value.outSpeedInByte
        }
    }

    var interval: Int {
        preferenceStore.networkRefreshRate
    }

    init() {
        lastTimestamp = Date().timeIntervalSince1970
        shellPipe("nettop -P -x -J interface,bytes_in,bytes_out -l0 -s \(interval)") { [self] string in
            let rows = string.split(separator: "\n").map { String($0) }
            let headers = rows[0].split(separator: " ").map { String($0.lowercased()) }

            guard
                let interfaceIndex = headers.firstIndex(of: "interface"),
                let inBytesIndex = headers.firstIndex(of: "bytes_in"),
                let outBytesIndex = headers.firstIndex(of: "bytes_out")
            else {
                return
            }

            let runningApps = NSWorkspace.shared.runningApplications
            let time = Date().timeIntervalSince1970
            let timeElapsed = time - lastTimestamp

            processes = rows.dropFirst().compactMap { row in
                let cols = row.split(separator: " ").map { String($0) }
                let interface = cols[interfaceIndex]
                let splitted = interface.split(separator: ".").map { String($0) }

                guard
                    splitted.count >= 2,
                    let pid = Int(splitted[1]),
                    let inBytes = Double(cols[inBytesIndex]),
                    let outBytes = Double(cols[outBytesIndex])
                else {
                    return nil
                }

                let lastIn = lastInBytes[pid]
                let lastOut = lastOutBytes[pid]

                lastInBytes[pid] = inBytes
                lastOutBytes[pid] = outBytes

                if lastIn == nil, lastOut == nil {
                    return nil
                }

                let speed = NetworkSpeed(
                    inSpeedInByte: lastIn.map { (inBytes - $0) / timeElapsed } ?? 0,
                    outSpeedInByte: lastOut.map { (outBytes - $0) / timeElapsed } ?? 0
                )

                guard speed.totalSpeedInByte > 0.1 else {
                    return nil
                }

                return ProcessNetworkUsage(
                    pid: pid,
                    command: Info.getProcessCommand(pid: pid) ?? splitted[0],
                    value: speed,
                    runningApp: runningApps.first(where: { $0.processIdentifier == pid })
                )
            }
            .sorted(by: { $0.value.totalSpeedInByte > $1.value.totalSpeedInByte })

            lastTimestamp = time
        }
    }
}
