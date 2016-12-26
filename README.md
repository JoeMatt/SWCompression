# SWCompression
[![GitHub license](https://img.shields.io/badge/license-MIT-lightgrey.svg)](https://raw.githubusercontent.com/tsolomko/SWCompression/master/LICENSE) [![CocoaPods](https://img.shields.io/cocoapods/p/SWCompression.svg)](https://cocoapods.org/pods/SWCompression) [![Swift 3](https://img.shields.io/badge/Swift-3.0.2-lightgrey.svg)](https://developer.apple.com/swift/)


[![Build Status](https://travis-ci.org/tsolomko/SWCompression.svg?branch=develop)](https://travis-ci.org/tsolomko/SWCompression) [![codecov](https://codecov.io/gh/tsolomko/SWCompression/branch/develop/graph/badge.svg)](https://codecov.io/gh/tsolomko/SWCompression)

[![CocoaPods](https://img.shields.io/cocoapods/v/SWCompression.svg)](https://cocoapods.org/pods/SWCompression)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)

A framework which contains implementations of some compression algorithms.
__Developed with Swift__

Why have you made compression framework?
----------------------------------------
There are a couple of reasons for this.

The main reason is that it is very educational and somewhat fun.

Secondly, if you are a Swift developer and you want to compress/decompress something in your project
you have to use either wrapper around system libraries (which is probably written in Objective-C)
or you have to use built-in Compression framework.
You might think that last option is what you need, but, frankly
that framework has a bit complicated API and somewhat questionable choice of supported compression algorithms.
And yes, it is also in Objective-C.

And here comes SWCompression: no Objective-C, pure Swift.

Features
----------------
- (De)compression algorithms:
  - LZMA/LZMA2
  - Deflate
  - BZip2
- Archives:
  - XZ
  - LZMA
  - GZip
  - Zlib
- Platform independent.
- _Swift only._

By the way, it seems like GZip, Deflate and Zlib implementations are **specification compliant**.

Installation
----------------

SWCompression can be integrated into your project either using CocoaPods, Carthage or Swift Package Manager.

##### CocoaPods
Add to your Podfile `pod 'SWCompression'`.

There are several sub-podspecs if you need only parts of framework's functionaliry.
Available subspecs:
  - SWCompression/LZMA
  - SWCompression/XZ
  - SWCompression/Deflate
  - SWCompression/Gzip
  - SWCompression/Zlib
  - SWCompression/BZip2
You can add some or all of them instead of `pod 'SWCompression'`

Also, do not forget to include `use_frameworks!` line in your Podfile.

To complete installation, run `pod install`.

_Note:_ Actually, there is one more subspec (SWCompression/Common) but it does not contain any end-user functions. This subspec is included in any other subspecs and should not be specified directly in Podfile.

##### Carthage
Add to  your Cartfile `github "tsolomko/SWCompression"`.

Then run `carthage update`.

Finally, drag and drop `SWCompression.framework` from `Carthage/Build` folder into the "Embedded Binaries" section on your targets' "General" tab.

##### Swift Package Manager
Add to you package dependecies `.Package(url: "https://github.com/tsolomko/SWCompression.git")`, for example like this:
```swift
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .Package(url: "https://github.com/tsolomko/SWCompression.git", majorVersion: 2)
    ]
)
```

More info about SPM you can find at [Swift Package Manager's Documentation](https://github.com/apple/swift-package-manager/tree/master/Documentation).

Usage
-------
If you'd like to decompress "deflated" data just use:
```swift
let data = try! Data(contentsOf: URL(fileURLWithPath: "path/to/file"),
                     options: .mappedIfSafe)
let decompressedData = try? Deflate.decompress(compressedData: data)
```
_Note:_ It is __highly recommended__ to specify `Data.ReadingOptions.mappedIfSafe`,
especially if you are working with large files,
so you don't run out of system memory.

However, it is unlikely that you will encounter deflated data outside of any archive.
So, in case of GZip archive you should use:
```swift
let decompressedData = try? GzipArchive.unarchive(archiveData: data)
```

One final note: every unarchive/decompress function can throw an error and
you are responsible for handling them.

##### Handling Errors
If you look at list of available error types and their cases,
you may be frightened by their number.
However, most of these cases (such as `XZError.WrongMagic`) exist for diagnostic purposes.

Thus, you only need to handle the most common type of error for your archive/algorithm.
For example:
```swift
do {
  let data = try Data(contentsOf: URL(fileURLWithPath: "path/to/file"),
                      options: .mappedIfSafe)
  let decompressedData = XZArchive.unarchive(archiveData: data)
} catch let error as XZError {
  <handle XZ related error here>
} catch let error {
  <handle all other errors here>
}
```

Why is it so slow?
------------------
Version 2.0 came with a great performance improvement.
Just look at the test results at 'Tests/Test Result'.
So if it's slow the first thing you should do is to make sure you are using version >= 2.0.

Is it still slow?
Maybe you are compiling SWCompression not for 'Release' but with 'Debug' build configuration?
For some reason, when framework is built for 'Debug' its performance __significantly__ worse.
You can once again check test results if you want to convince yourself that this is the case.

Finally, SWCompression's code is not as optimized as original C/C++ versions of corresponding algorithms,
so some difference in speed is expected.

To sum up, it is __highly recommended__ to build SWCompression with 'Release' configuration and use the latest version (at least 2.0).

Future plans
-------------
- Tar unarchiving.
- Deflate compression.
- BZip2 compression.
- Something else...

References
-----------
- [pyflate](http://www.paul.sladen.org/projects/pyflate/)
- [Deflate specification](https://www.ietf.org/rfc/rfc1951.txt)
- [GZip specification](https://www.ietf.org/rfc/rfc1952.txt)
- [Zlib specfication](https://www.ietf.org/rfc/rfc1950.txt)
- [XZ specification](http://tukaani.org/xz/xz-file-format-1.0.4.txt)
- [Wikipedia article about LZMA](https://en.wikipedia.org/wiki/Lempel–Ziv–Markov_chain_algorithm)
- [LZMA SDK and specification](http://www.7-zip.org/sdk.html)
