//
//  GzipArchive.swift
//  SWCompression
//
//  Created by Timofey Solomko on 29.10.16.
//  Copyright © 2016 Timofey Solomko. All rights reserved.
//

import Foundation

/**
 Error happened during unarchiving gzip archive.
 It may indicate that either the data is damaged or it might not be gzip archive at all.

 - `WrongMagic`: first two bytes of archive were not 31 and 139.
 - `WrongCompressionMethod`: unsupported compression method (not 8 aka Deflate).
 - `WrongFlags`: unsupported flags (reserved flags weren't 0).
 - `WrongHeaderCRC`: computed Cyclic Redundancy Check of archive's header
        didn't match the archive's value.
 - `WrongCRC`: computed Cyclic Redundancy Check of uncompressed data didn't match the archive's value.
 - `WrongISize`: size of uncompressed data modulo 2^32 didn't match the archive's value.
 */
public enum GzipError: Error {
    /// First two bytes of archive were not 31 and 139.
    case WrongMagic
    /// Compression method was other than 8 which is the only supported one.
    case WrongCompressionMethod
    /// Reserved flags bits were not equal to 0.
    case WrongFlags
    /// Computed CRC of header didn't match the value stored in the archive.
    case WrongHeaderCRC
    /// Computed CRC of uncompressed data didn't match the value stored in the archive.
    case WrongCRC
    /// Computed isize didn't match the value stored in the archive.
    case WrongISize
}

/// A strucutre which provides information about gzip archive.
public struct GzipHeader {

    struct Flags {
        static let ftext: UInt8 = 0x01
        static let fhcrc: UInt8 = 0x02
        static let fextra: UInt8 = 0x04
        static let fname: UInt8 = 0x08
        static let fcomment: UInt8 = 0x10
    }

    /// Supported compression methods in gzip archive.
    public enum CompressionMethod: Int {
        case deflate = 8
    }

    /// Type of file system on which gzip archive was created.
    public enum FileSystemType: Int {
        case fat = 0
        case amiga = 1
        case vms = 2
        case unix = 3
        case vm = 4
        case atariTos = 5
        case hpfs = 6
        case macintosh = 7
        case zSystem = 8
        case cpm = 9
        case tops20 = 10
        case ntfs = 11
        case qdos = 12
        case acornRiscos = 13
        case unknown = 255
    }

    /// Compression method of archive. Always equals to `.deflate`.
    public let compressionMethod: CompressionMethod
    /// The most recent modification time of the original file.
    public let modificationTime: Date
    /// Type of file system on which compression took place.
    public let osType: FileSystemType
    /// Name of the original file.
    public let originalFileName: String?
    /// Comment inside the archive.
    public let comment: String?

    /**
        Initializes the structure with the values of first 'member' in gzip archive presented in `archiveData`.

        If data passed is not actually a gzip archive, `GzipError` will be thrown.

        - Parameter archiveData: Data compressed with gzip.

        - Throws: `GzipError`. It may indicate that either the data is damaged or
        it might not be compressed with gzip at all.
    */

    public init(archiveData: Data) throws {
        let pointerData = DataWithPointer(data: archiveData, bitOrder: .reversed)
        try self.init(pointerData)
    }

    init(_ pointerData: DataWithPointer) throws {
        // First two bytes should be correct 'magic' bytes
        let magic = pointerData.intFromAlignedBytes(count: 2)
        guard magic == 0x8b1f else { throw GzipError.WrongMagic }
        var headerBytes: [UInt8] = [0x1f, 0x8b]

        // Third byte is a method of compression. Only type 8 (DEFLATE) compression is supported
        let method = pointerData.alignedByte()
        guard method == 8 else { throw GzipError.WrongCompressionMethod }
        headerBytes.append(method)

        self.compressionMethod = .deflate

        let flags = pointerData.alignedByte()
        guard (flags & 0x20 == 0) && (flags & 0x40 == 0) && (flags & 0x80 == 0) else { throw GzipError.WrongFlags }
        headerBytes.append(flags)

        let mtime = pointerData.intFromAlignedBytes(count: 4)
        for i in 0..<4 {
            headerBytes.append(((mtime & (0xFF << (i * 8))) >> (i * 8)).toUInt8())
        }
        self.modificationTime = Date(timeIntervalSince1970: TimeInterval(mtime))

        let extraFlags = pointerData.alignedByte()
        headerBytes.append(extraFlags)

        self.osType = FileSystemType(rawValue: pointerData.alignedByte().toInt()) ?? .unknown
        headerBytes.append(self.osType.rawValue.toUInt8())

        // Some archives may contain extra fields
        if flags & Flags.fextra != 0 {
            let xlen = pointerData.intFromAlignedBytes(count: 2)
            for i in 0..<2 {
                headerBytes.append(((xlen & (0xFF << (i * 8))) >> (i * 8)).toUInt8())
            }
            for _ in 0..<xlen {
                headerBytes.append(pointerData.alignedByte())
            }
        }

        // Some archives may contain source file name (this part ends with zero byte)
        if flags & Flags.fname != 0 {
            var fnameBytes: [UInt8] = []
            while true {
                let byte = pointerData.alignedByte()
                guard byte != 0 else { break }
                fnameBytes.append(byte)
                headerBytes.append(byte)
            }
            self.originalFileName = String(data: Data(fnameBytes), encoding: .utf8)
        } else {
            self.originalFileName = nil
        }

        // Some archives may contain comment (this part also ends with zero)
        if flags & Flags.fcomment != 0 {
            var fcommentBytes: [UInt8] = []
            while true {
                let byte = pointerData.alignedByte()
                guard byte != 0 else { break }
                fcommentBytes.append(byte)
                headerBytes.append(byte)
            }
            self.comment = String(data: Data(fcommentBytes), encoding: .utf8)
        } else {
            self.comment = nil
        }

        // Some archives may contain 2-bytes checksum
        if flags & Flags.fhcrc != 0 {
            // Note: it is not actual CRC-16, it is just two least significant bytes of CRC-32.
            let crc16 = pointerData.intFromAlignedBytes(count: 2)
            let ourCRC32 = CheckSums.crc32(headerBytes)
            guard ourCRC32 & 0xFFFF == crc16 else { throw GzipError.WrongHeaderCRC }
        }
    }

}

/// A class with unarchive function for gzip archives.
public final class GzipArchive: Archive {

    /**
     Unarchives gzip archive stored in `archiveData`.

     If data passed is not actually a gzip archive, `GzipError` will be thrown.

     If data inside the archive is not actually compressed with DEFLATE algorithm, `DeflateError` will be thrown.

     - Note: This function is specification compliant.

     - Parameter archiveData: Data compressed with gzip.

     - Throws: `DeflateError` or `GzipError` depending on the type of inconsistency in data.
     It may indicate that either the data is damaged or it might not be compressed with gzip or DEFLATE at all.

     - Returns: Unarchived data.
     */
    public static func unarchive(archiveData data: Data) throws -> Data {
        /// Object with input data which supports convenient work with bit shifts.
        var pointerData = DataWithPointer(data: data, bitOrder: .reversed)

        var out: [UInt8] = []

        while !pointerData.isAtTheEnd {
            _ = try GzipHeader(pointerData)

            let memberData = try Deflate.decompress(&pointerData)

            let crc32 = pointerData.intFromAlignedBytes(count: 4)
            guard CheckSums.crc32(memberData) == crc32 else { throw GzipError.WrongCRC }

            let isize = pointerData.intFromAlignedBytes(count: 4)
            guard memberData.count % (1 << 32) == isize else { throw GzipError.WrongISize }

            out.append(contentsOf: memberData)
        }

        return Data(bytes: out)
    }

}
