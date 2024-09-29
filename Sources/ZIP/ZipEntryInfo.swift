// Copyright (c) 2024 Timofey Solomko
// Licensed under MIT License
//
// See LICENSE for license information

import Foundation
import BitByteData

/// Provides access to information about an entry from the ZIP container.
public struct ZipEntryInfo: ContainerEntryInfo, Sendable {

    // MARK: ContainerEntryInfo

    public let name: String

    public let size: Int?

    public let type: ContainerEntryType

    /**
     Entry's last access time (`nil`, if not available).

     Set from different sources in the following preference order:
     1. Extended timestamp extra field (most common on UNIX-like systems).
     2. NTFS extra field.
    */
    public let accessTime: Date?

    /**
     Entry's creation time (`nil`, if not available).

     Set from different sources in the following preference order:
     1. Extended timestamp extra field (most common on UNIX-like systems).
     2. NTFS extra field.
     */
    public let creationTime: Date?

    /**
     Entry's last modification time.

     Set from different sources in the following preference order:
     1. Extended timestamp extra field (most common on UNIX-like systems).
     2. NTFS extra field.
     3. ZIP container's own storage (in Central Directory entry).
     */
    public let modificationTime: Date?

    /**
     Entry's permissions in POSIX format.
     May have meaningless value if origin file system's attributes weren't POSIX compatible.
     */
    public let permissions: Permissions?

    // MARK: ZIP specific

    /// Entry's comment.
    public let comment: String

    /**
     Entry's external file attributes. ZIP internal property.
     May be useful when origin file system's attributes weren't POSIX compatible.
     */
    public let externalFileAttributes: UInt32

    /// Entry's attributes in DOS format.
    public let dosAttributes: DosAttributes?

    /// True, if entry is likely to be text or ASCII file.
    public let isTextFile: Bool

    /// File system type of container's origin.
    public let fileSystemType: FileSystemType

    /// Entry's compression method.
    public let compressionMethod: CompressionMethod

    /**
     ID of entry's owner.

     Set from different sources in the following preference order, if possible:
     1. Info-ZIP New Unix extra field.
     2. Info-ZIP Unix extra field.
     */
    public let ownerID: Int?

    /**
     ID of the group of entry's owner.

     Set from different sources in the following preference order, if possible:
     1. Info-ZIP New Unix extra field.
     2. Info-ZIP Unix extra field.
     */
    public let groupID: Int?

    /**
     Entry's custom extra fields from both Central Directory and Local Header.

     - Note: No particular order of extra fields is guaranteed.
     */
    public let customExtraFields: [any ZipExtraField]

    /// CRC32 of entry's data.
    public let crc: UInt32

    init(_ byteReader: LittleEndianByteReader, _ cdEntry: ZipCentralDirectoryEntry, _ localHeader: ZipLocalHeader,
         _ hasDataDescriptor: Bool) {
        self.name = cdEntry.fileName

        // Set Modification Time.
        if let mtime = cdEntry.extendedTimestampExtraField?.mtime {
            // Extended Timestamp extra field.
            self.modificationTime = Date(timeIntervalSince1970: TimeInterval(mtime))
        } else if let mtime = cdEntry.ntfsExtraField?.mtime {
            // NTFS extra field.
            self.modificationTime = Date(mtime)
        } else {
            // Native ZIP modification time.
            let dosDate = cdEntry.lastModFileDate.toInt()

            let day = dosDate & 0x1F
            let month = (dosDate & 0x1E0) >> 5
            let year = 1980 + ((dosDate & 0xFE00) >> 9)

            let dosTime = cdEntry.lastModFileTime.toInt()

            let seconds = 2 * (dosTime & 0x1F)
            let minutes = (dosTime & 0x7E0) >> 5
            let hours = (dosTime & 0xF800) >> 11

            self.modificationTime = DateComponents(calendar: Calendar.current, timeZone: TimeZone.current,
                                                   year: year, month: month, day: day,
                                                   hour: hours, minute: minutes, second: seconds).date
        }

        // Set Creation Time.
        if let ctime = localHeader.extendedTimestampExtraField?.ctime {
            // Extended Timestamp extra field.
            self.creationTime = Date(timeIntervalSince1970: TimeInterval(ctime))
        } else if let ctime = cdEntry.ntfsExtraField?.ctime {
            // NTFS extra field.
            self.creationTime = Date(ctime)
        } else {
            self.creationTime = nil
        }

        // Set Creation Time.
        if let atime = localHeader.extendedTimestampExtraField?.atime {
            // Extended Timestamp extra field.
            self.accessTime = Date(timeIntervalSince1970: TimeInterval(atime))
        } else if let atime = cdEntry.ntfsExtraField?.atime {
            // NTFS extra field.
            self.accessTime = Date(atime)
        } else {
            self.accessTime = nil
        }

        self.size = (hasDataDescriptor ? cdEntry.uncompSize : localHeader.uncompSize).toInt()

        self.externalFileAttributes = cdEntry.externalFileAttributes
        self.permissions = Permissions(rawValue: (0x0FFF0000 & cdEntry.externalFileAttributes) >> 16)
        self.dosAttributes = DosAttributes(rawValue: 0xFF & cdEntry.externalFileAttributes)

        // Set entry type.
        if let unixType = ContainerEntryType((0xF0000000 & cdEntry.externalFileAttributes) >> 16) {
            self.type = unixType
        } else if let dosAttributes = self.dosAttributes {
            if dosAttributes.contains(.directory) {
                self.type = .directory
            } else {
                self.type = .regular
            }
        } else if size == 0 && cdEntry.fileName.last == "/" {
            self.type = .directory
        } else {
            self.type = .regular
        }

        self.comment = cdEntry.fileComment
        self.isTextFile = cdEntry.internalFileAttributes & 0x1 != 0
        self.fileSystemType = FileSystemType(cdEntry.versionMadeBy)
        self.compressionMethod = CompressionMethod(localHeader.compressionMethod)
        self.ownerID = localHeader.infoZipNewUnixExtraField?.uid ?? localHeader.infoZipUnixExtraField?.uid
        self.groupID = localHeader.infoZipNewUnixExtraField?.gid ?? localHeader.infoZipUnixExtraField?.gid
        self.crc = hasDataDescriptor ? cdEntry.crc32 : localHeader.crc32

        // Custom extra fields.
        var customExtraFields = cdEntry.customExtraFields
        customExtraFields.append(contentsOf: localHeader.customExtraFields)
        self.customExtraFields = customExtraFields
    }
}

extension ZipEntryInfo: Codable {
    enum CodingKeys: String, CodingKey {
        case name, size, type, accessTime, creationTime, modificationTime, permissions
        case comment, externalFileAttributes, dosAttributes, isTextFile, fileSystemType
        case compressionMethod, ownerID, groupID, customExtraFields, crc
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        name = try container.decode(String.self, forKey: .name)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        type = try container.decode(ContainerEntryType.self, forKey: .type)
        accessTime = try container.decodeIfPresent(Date.self, forKey: .accessTime)
        creationTime = try container.decodeIfPresent(Date.self, forKey: .creationTime)
        modificationTime = try container.decodeIfPresent(Date.self, forKey: .modificationTime)
        permissions = try container.decodeIfPresent(Permissions.self, forKey: .permissions)
        comment = try container.decode(String.self, forKey: .comment)
        externalFileAttributes = try container.decode(UInt32.self, forKey: .externalFileAttributes)
        dosAttributes = try container.decodeIfPresent(DosAttributes.self, forKey: .dosAttributes)
        isTextFile = try container.decode(Bool.self, forKey: .isTextFile)
        fileSystemType = try container.decode(FileSystemType.self, forKey: .fileSystemType)
        compressionMethod = try container.decode(CompressionMethod.self, forKey: .compressionMethod)
        ownerID = try container.decodeIfPresent(Int.self, forKey: .ownerID)
        groupID = try container.decodeIfPresent(Int.self, forKey: .groupID)
//        customExtraFields = try container.decode([ZipExtraField].self, forKey: .customExtraFields)
        customExtraFields = []
        crc = try container.decode(UInt32.self, forKey: .crc)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(size, forKey: .size)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(accessTime, forKey: .accessTime)
        try container.encodeIfPresent(creationTime, forKey: .creationTime)
        try container.encodeIfPresent(modificationTime, forKey: .modificationTime)
        try container.encodeIfPresent(permissions, forKey: .permissions)
        try container.encode(comment, forKey: .comment)
        try container.encode(externalFileAttributes, forKey: .externalFileAttributes)
        try container.encodeIfPresent(dosAttributes, forKey: .dosAttributes)
        try container.encode(isTextFile, forKey: .isTextFile)
        try container.encode(fileSystemType, forKey: .fileSystemType)
        try container.encode(compressionMethod, forKey: .compressionMethod)
        try container.encodeIfPresent(ownerID, forKey: .ownerID)
        try container.encodeIfPresent(groupID, forKey: .groupID)
//        try container.encode(customExtraFields, forKey: .customExtraFields)
        try container.encode(crc, forKey: .crc)
    }
}
