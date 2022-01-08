// Copyright (c) 2021 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import SWCompression
import SwiftCLI

class TarCommand: Command {

    let name = "tar"
    let shortDescription = "Extracts a TAR container"

    @Flag("-z", "--gz", description: "With -e: decompress with GZip first; with -c: compress container with GZip")
    var gz: Bool

    @Flag("-j", "--bz2", description: "With -e: decompress with BZip2 first; with -c: compress container with BZip2")
    var bz2: Bool

    @Flag("-x", "--xz", description: "With -e: decompress with XZ first; with -c: not supported")
    var xz: Bool

    @Flag("-i", "--info", description: "Print the list of entries in a container and their attributes")
    var info: Bool

    @Key("-e", "--extract", description: "Extract a container into specified directory")
    var extract: String?

    @Flag("-f", "--format", description: "Print the \"format\" of a container")
    var format: Bool

    @Key("-c", "--create", description: "Create a new container containing the specified file/directory (recursively)")
    var create: String?

    @Key("--use-format", description: "Use specified TAR format when creating a container; available options: prePosix, ustar, gnu, pax")
    var useFormat: TarContainer.Format?

    @Flag("-v", "--verbose", description: "Print the list of extracted files and directories.")
    var verbose: Bool

    @Flag("--use-rw-api", description: "Use TarReader/TarWriter APIs (may reduce RAM consumption)")
    var useRwApi: Bool

    var optionGroups: [OptionGroup] {
        return [.atMostOne($gz, $bz2, $xz), .exactlyOne($info, $extract, $format, $create)]
    }

    @Param var input: String

    func execute() throws {
        if useRwApi {
            try executeUseRwApi()
            return
        }
        if self.useFormat != nil && self.create == nil {
            print("WARNING: --use-format option is ignored without -c/--create option")
        }

        var fileData: Data
        if self.create == nil {
            fileData = try Data(contentsOf: URL(fileURLWithPath: self.input),
                                    options: .mappedIfSafe)

            if gz {
                fileData = try GzipArchive.unarchive(archive: fileData)
            } else if bz2 {
                fileData = try BZip2.decompress(data: fileData)
            } else if xz {
                fileData = try XZArchive.unarchive(archive: fileData)
            }
        } else {
            fileData = Data()
        }

        if info {
            let entries = try TarContainer.info(container: fileData)
            swcomp.printInfo(entries)
        } else if let outputPath = self.extract {
            if try !isValidOutputDirectory(outputPath, create: true) {
                print("ERROR: Specified output path already exists and is not a directory.")
                exit(1)
            }

            let entries = try TarContainer.open(container: fileData)
            try swcomp.write(entries, outputPath, verbose)
        } else if format {
            let format = try TarContainer.formatOf(container: fileData)
            switch format {
            case .prePosix:
                print("TAR format: pre-POSIX")
            case .ustar:
                print("TAR format: POSIX aka \"ustar\"")
            case .gnu:
                print("TAR format: POSIX with GNU extensions")
            case .pax:
                print("TAR format: PAX")
            }
        } else if let inputPath = self.create {
            guard !xz else {
                print("ERROR: XZ compression is not supported when creating a container.")
                exit(1)
            }

            let fileManager = FileManager.default

            guard !fileManager.fileExists(atPath: self.input) else {
                print("ERROR: Output path already exists.")
                exit(1)
            }

            guard fileManager.fileExists(atPath: inputPath) else {
                print("ERROR: Specified input path doesn't exist.")
                exit(1)
            }
            if verbose {
                print("Creating new container at \"\(self.input)\" from \"\(inputPath)\"")
                print("d = directory, f = file, l = symbolic link")
            }
            let entries = try TarEntry.createEntries(inputPath, verbose)
            var outData = TarContainer.create(from: entries, force: self.useFormat ?? .pax)
            let outputURL = URL(fileURLWithPath: self.input)
            if gz {
                let fileName = outputURL.lastPathComponent
                outData = try GzipArchive.archive(data: outData, fileName: fileName.isEmpty ? nil : fileName,
                                                  writeHeaderCRC: true)
            } else if bz2 {
                outData = BZip2.compress(data: outData)
            }
            try outData.write(to: outputURL)
        }
    }

    private func executeUseRwApi() throws {
        if self.useFormat != nil && self.create == nil {
            print("WARNING: --use-format option is ignored without -c/--create option")
        }

        if gz {
            print("ERROR: -z is unsupported with the --use-rw-api options.")
            exit(1)
        } else if bz2 {
            print("ERROR: -j is unsupported with the --use-rw-api options.")
            exit(1)
        } else if xz {
            print("ERROR: -x is unsupported with the --use-rw-api options.")
            exit(1)
        } else if format {
            print("ERROR: -f is unsupported with the --use-rw-api options.")
            exit(1)
        }

        if info {
            guard let handle = FileHandle(forReadingAtPath: self.input) else {
                print("ERROR: Unable to open input file.")
                exit(1)
            }
            var reader = TarReader(fileHandle: handle)
            var isFinished = false
            while !isFinished {
                isFinished = try reader.process { (entry: TarEntry?) -> Bool in
                    guard entry != nil
                        else { return true }
                    print(entry!.info)
                    print("------------------\n")
                    return false
                }
            }
            try handle.closeHandleCompat()
        } else if let outputPath = self.extract {
            if try !isValidOutputDirectory(outputPath, create: true) {
                print("ERROR: Specified output path already exists and is not a directory.")
                exit(1)
            }
            if verbose {
                print("d = directory, f = file, l = symbolic link")
            }

            guard let handle = FileHandle(forReadingAtPath: self.input) else {
                print("ERROR: Unable to open input file.")
                exit(1)
            }
            var reader = TarReader(fileHandle: handle)
            let fileManager = FileManager.default
            let outputURL = URL(fileURLWithPath: outputPath)
            var directoryAttributes = [(attributes: [FileAttributeKey: Any], path: String)]()
            var isFinished = false
            while !isFinished {
                isFinished = try reader.process { (entry: TarEntry?) -> Bool in
                    guard entry != nil
                        else { return true }
                    if entry!.info.type == .directory {
                        directoryAttributes.append(try writeDirectory(entry!, outputURL, verbose))
                    } else {
                        try writeFile(entry!, outputURL, verbose)
                    }
                    return false
                }
            }
            try handle.closeHandleCompat()

            for tuple in directoryAttributes {
                try fileManager.setAttributes(tuple.attributes, ofItemAtPath: tuple.path)
            }
        } else if let inputPath = self.create {
            let fileManager = FileManager.default

            guard !fileManager.fileExists(atPath: self.input) else {
                print("ERROR: Output path already exists.")
                exit(1)
            }

            guard fileManager.fileExists(atPath: inputPath) else {
                print("ERROR: Specified input path doesn't exist.")
                exit(1)
            }
            if verbose {
                print("Creating new container at \"\(self.input)\" from \"\(inputPath)\"")
                print("d = directory, f = file, l = symbolic link")
            }

            let outputURL = URL(fileURLWithPath: self.input)
            try "".write(to: outputURL, atomically: true, encoding: .utf8)
            let handle = try FileHandle(forWritingTo: outputURL)
            var writer = TarWriter(fileHandle: handle, format: self.useFormat ?? .pax)
            try TarEntry.generateEntries(&writer, inputPath, verbose)
            try writer.finalize()
            try handle.closeHandleCompat()
        }
    }

}

fileprivate extension FileHandle {

    func closeHandleCompat() throws {
        #if compiler(<5.2)
            self.closeFile()
        #else
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try self.close()
            } else {
                self.closeFile()
            }
        #endif
    }

}