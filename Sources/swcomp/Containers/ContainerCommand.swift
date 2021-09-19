// Copyright (c) 2021 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import SWCompression
import SwiftCLI

protocol ContainerCommand: Command {

    associatedtype ContainerType: Container

    var info: Flag { get }
    var extract: Key<String> { get }
    var verbose: Flag { get }

    var archive: Parameter { get }

}

extension ContainerCommand {

    var optionGroups: [OptionGroup] {
        let actions = OptionGroup(options: [info, extract], restriction: .exactlyOne)
        return [actions]
    }

    func execute() throws {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: self.archive.value),
                                options: .mappedIfSafe)
        if info.value {
            let entries = try ContainerType.info(container: fileData)
            swcomp.printInfo(entries)
        } else if let outputPath = self.extract.value {
            if try !isValidOutputDirectory(outputPath, create: true) {
                print("ERROR: Specified path already exists and is not a directory.")
                exit(1)
            }

            let entries = try ContainerType.open(container: fileData)
            try swcomp.write(entries, outputPath, verbose.value)
        }
    }

}
