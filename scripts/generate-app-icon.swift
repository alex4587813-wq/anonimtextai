#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum IconError: Error, CustomStringConvertible {
    case invalidArguments
    case cannotReadSource(String)
    case cannotCreateContext(Int)
    case cannotCreateImage(Int)
    case cannotCreateDestination(String)
    case cannotWriteImage(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Использование: generate-app-icon.swift <source.png> <output-directory>"
        case .cannotReadSource(let path):
            return "Не удалось прочитать исходное изображение: \(path)"
        case .cannotCreateContext(let size):
            return "Не удалось создать графический контекст \(size)x\(size)"
        case .cannotCreateImage(let size):
            return "Не удалось сформировать изображение \(size)x\(size)"
        case .cannotCreateDestination(let path):
            return "Не удалось создать файл: \(path)"
        case .cannotWriteImage(let path):
            return "Не удалось записать изображение: \(path)"
        }
    }
}

func renderIcon(source: CGImage, size: Int) throws -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw IconError.cannotCreateContext(size)
    }

    context.interpolationQuality = .high
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))

    // Маска совпадает с внешним скруглением исходного изображения и делает
    // чёрные углы прозрачными для Windows и macOS.
    let radius = CGFloat(size) * 0.218
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let mask = CGPath(
        roundedRect: bounds,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )
    context.addPath(mask)
    context.clip()
    context.draw(source, in: bounds)

    guard let image = context.makeImage() else {
        throw IconError.cannotCreateImage(size)
    }
    return image
}

func pngData(from image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw IconError.cannotCreateDestination("данные PNG")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.cannotWriteImage("данные PNG")
    }
    return data as Data
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let data = try pngData(from: image)
    try data.write(to: url, options: .atomic)
}

func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value.littleEndian) { Array($0) }
}

func bigEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    withUnsafeBytes(of: value.bigEndian) { Array($0) }
}

func writeICO(images: [(size: Int, data: Data)], to url: URL) throws {
    let entrySize = 16
    let headerSize = 6
    var offset = headerSize + entrySize * images.count
    var file = Data()

    file.append(contentsOf: littleEndianBytes(UInt16(0)))
    file.append(contentsOf: littleEndianBytes(UInt16(1)))
    file.append(contentsOf: littleEndianBytes(UInt16(images.count)))

    for item in images {
        file.append(UInt8(item.size == 256 ? 0 : item.size))
        file.append(UInt8(item.size == 256 ? 0 : item.size))
        file.append(0)
        file.append(0)
        file.append(contentsOf: littleEndianBytes(UInt16(1)))
        file.append(contentsOf: littleEndianBytes(UInt16(32)))
        file.append(contentsOf: littleEndianBytes(UInt32(item.data.count)))
        file.append(contentsOf: littleEndianBytes(UInt32(offset)))
        offset += item.data.count
    }

    for item in images {
        file.append(item.data)
    }

    try file.write(to: url, options: .atomic)
}

func writeICNS(images: [(type: String, data: Data)], to url: URL) throws {
    let payloadLength = images.reduce(0) { result, item in
        result + 8 + item.data.count
    }
    var file = Data("icns".utf8)
    file.append(contentsOf: bigEndianBytes(UInt32(8 + payloadLength)))

    for item in images {
        file.append(Data(item.type.utf8))
        file.append(contentsOf: bigEndianBytes(UInt32(8 + item.data.count)))
        file.append(item.data)
    }

    try file.write(to: url, options: .atomic)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconError.invalidArguments
    }

    let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
    let iconsetURL = outputURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
    let fileManager = FileManager.default

    guard
        let sourceImage = NSImage(contentsOf: sourceURL),
        let source = sourceImage.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    else {
        throw IconError.cannotReadSource(sourceURL.path)
    }

    try fileManager.createDirectory(
        at: outputURL,
        withIntermediateDirectories: true
    )
    if fileManager.fileExists(atPath: iconsetURL.path) {
        try fileManager.removeItem(at: iconsetURL)
    }
    try fileManager.createDirectory(
        at: iconsetURL,
        withIntermediateDirectories: true
    )

    let master = try renderIcon(source: source, size: 1024)
    try writePNG(master, to: outputURL.appendingPathComponent("AppIcon.png"))

    let iconsetFiles: [(name: String, size: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    for item in iconsetFiles {
        let image = item.size == 1024 ? master : try renderIcon(source: source, size: item.size)
        try writePNG(image, to: iconsetURL.appendingPathComponent(item.name))
    }

    let icoSizes = [16, 24, 32, 48, 64, 128, 256]
    let icoImages = try icoSizes.map { size -> (size: Int, data: Data) in
        let image = try renderIcon(source: source, size: size)
        return (size, try pngData(from: image))
    }
    try writeICO(images: icoImages, to: outputURL.appendingPathComponent("AppIcon.ico"))

    let icnsTypes: [(type: String, size: Int)] = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
    ]
    let icnsImages = try icnsTypes.map { item -> (type: String, data: Data) in
        let image = item.size == 1024 ? master : try renderIcon(source: source, size: item.size)
        return (item.type, try pngData(from: image))
    }
    try writeICNS(images: icnsImages, to: outputURL.appendingPathComponent("AppIcon.icns"))

    print("[icon] Подготовлен PNG: \(outputURL.appendingPathComponent("AppIcon.png").path)")
    print("[icon] Подготовлен ICO: \(outputURL.appendingPathComponent("AppIcon.ico").path)")
    print("[icon] Подготовлен ICNS: \(outputURL.appendingPathComponent("AppIcon.icns").path)")
    print("[icon] Подготовлен iconset: \(iconsetURL.path)")
} catch {
    fputs("[icon] Ошибка: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
