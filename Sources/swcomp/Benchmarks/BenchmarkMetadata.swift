// Copyright (c) 2024 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation

enum BenchmarkError: Error {
    case invalidInput
    case invalidOutput
    case benchmarkUnsupportedOs
}

struct BenchmarkMetadata: Codable, Equatable {

    var timestamp: TimeInterval?
    var osInfo: String
    var swiftVersion: String
    var swcVersion: String
    var description: String?

#if os(macOS)
    private static func run(command: URL, arguments: [String] = []) throws -> String {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.executableURL = command
        task.arguments = arguments
        task.standardInput = nil

        try task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)!
        return output
    }
#endif

    private static func getExecURL(for command: String) throws -> URL {
        let args = ["-c", "which \(command)"]
        #if os(Windows)
            swcompExit(.benchmarkCannotGetSubcommandPathWindows)
        #elseif os(macOS)
            let output = try BenchmarkMetadata.run(command: URL(fileURLWithPath: "/bin/sh"), arguments: args)
            return URL(fileURLWithPath: String(output.dropLast()))
        #else
            throw BenchmarkError.benchmarkUnsupportedOs
        #endif
    }

    private static func getOsInfo() throws -> String {
        #if os(Linux)
            return try BenchmarkMetadata.run(command: BenchmarkMetadata.getExecURL(for: "uname"), arguments: ["-a"])
        #else
            #if os(Windows)
                return "Unknown Windows OS"
            #elseif os(macOS)
                return try BenchmarkMetadata.run(command: BenchmarkMetadata.getExecURL(for: "sw_vers"))
            #else
                throw BenchmarkError.benchmarkUnsupportedOs
            #endif
        #endif
    }

    init(_ description: String?, _ preserveTimestamp: Bool) throws {
        self.timestamp = preserveTimestamp ? Date.timeIntervalSinceReferenceDate : nil
        self.osInfo = try BenchmarkMetadata.getOsInfo()
        self.swcVersion = _SWC_VERSION
        self.description = description
        #if os(Windows)
            self.swiftVersion = "Unknown Swift version on Windows"
        #elseif os(macOS)
            self.swiftVersion = try BenchmarkMetadata.run(command: BenchmarkMetadata.getExecURL(for: "swift"),
                                                          arguments: ["-version"])
        #else
            throw BenchmarkError.benchmarkUnsupportedOs
        #endif
    }

    func print() {
        Swift.print("OS Info: \(self.osInfo)", terminator: "")
        Swift.print("Swift version: \(self.swiftVersion)", terminator: "")
        Swift.print("SWC version: \(self.swcVersion)")
        if let timestamp = self.timestamp {
            Swift.print("Timestamp: " +
                DateFormatter.localizedString(from: Date(timeIntervalSinceReferenceDate: timestamp),
                                            dateStyle: .short, timeStyle: .short))
        }
        if let description = self.description {
            Swift.print("Description: \(description)")
        }
        Swift.print()
    }

}
