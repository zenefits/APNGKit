//
//  Frame.swift
//  APNGKit
//
//  Created by Wei Wang on 15/8/27.
//
//  Copyright (c) 2016 Wei Wang <onevcat@gmail.com>
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import UIKit

public class SharedFrame: UIImage {
    static var allocatedCount: Int = 0
    static var deallocatedCount: Int = 0

    init(bytes: UnsafeMutablePointer<UInt8>, length: Int, duration: TimeInterval) {
        self.bytes = bytes
        self.length = length
        self._duration = duration
        super.init()
    }

    init(CGImage: CGImage, scale: CGFloat, bytes: UnsafeMutablePointer<UInt8>, length: Int, duration: TimeInterval) {
        self.bytes = bytes
        self.length = length
        self._duration = duration
        super.init(cgImage: CGImage, scale: scale, orientation: .up)
    }

    required convenience public init(imageLiteral name: String) {
        fatalError("init(imageLiteral:) has not been implemented")
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required convenience public init(imageLiteralResourceName name: String) {
        fatalError("init(imageLiteralResourceName:) has not been implemented")
    }

    let length: Int
    let bytes: UnsafeMutablePointer<UInt8>?
    let _duration: TimeInterval
    public override var duration: TimeInterval {
        return _duration
    }

    deinit {
        bytes?.deinitialize(count: length)
        bytes?.deallocate(capacity: length)
    }
}

/**
*  Represents a frame in an APNG file.
*  It contains a whole IDAT chunk data for a PNG image.
*/
struct Frame {
    
    var image: UIImage?
    
    /// Data chunk.
    var bytes: UnsafeMutablePointer<UInt8>

    /// An array of raw data row pointer. A decoder should fill this area with image raw data.
    lazy var byteRows: Array<UnsafeMutableRawPointer> = {
        var array = Array<UnsafeMutableRawPointer>()

        let height = self.length / self.bytesInRow
        for i in 0 ..< height {
            let pointer = self.bytes.advanced(by: i * self.bytesInRow)
            array.append(pointer)
        }
        return array
    }()

    let length: Int

    /// How many bytes in a row. Regularly it is width * (bitDepth / 2)
    let bytesInRow: Int

    var duration: TimeInterval = 0

    init(length: UInt32, bytesInRow: UInt32) {
        self.length = Int(length)
        self.bytesInRow = Int(bytesInRow)

        self.bytes = UnsafeMutablePointer<UInt8>.allocate(capacity: self.length)
        self.bytes.initialize(to: 0)
        memset(self.bytes, 0, self.length)
    }

    func clean() {
        bytes.deinitialize(count: length)
        bytes.deallocate(capacity: length)
    }

    var sharedFrame: SharedFrame?
    mutating func createSharedFrame(width: Int, height: Int, bits: Int, scale: CGFloat) -> SharedFrame {
        // http://stackoverflow.com/a/39612298
        let releaseMaskImagePixelData: CGDataProviderReleaseDataCallback = { (info: UnsafeMutableRawPointer?, data: UnsafeRawPointer, size: Int) -> () in
            return
        }
        
        let provider = CGDataProvider(dataInfo: nil, data: bytes, size: length, releaseData: releaseMaskImagePixelData)

        if let imageRef = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits * 4, bytesPerRow: bytesInRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: [CGBitmapInfo.byteOrder32Big, CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)],
                                  provider: provider!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        {
            sharedFrame = SharedFrame.init(CGImage: imageRef, scale: scale, bytes: bytes, length: length, duration: duration)
            return sharedFrame!
        } else {
            sharedFrame = SharedFrame.init(bytes: bytes, length: length, duration: duration)
            return sharedFrame!
        }
    }

    mutating func updateCGImageRef(_ width: Int, height: Int, bits: Int, scale: CGFloat, blend: Bool) {
        let unusedCallback: CGDataProviderReleaseDataCallback = { optionalPointer, pointer, valueInt in }
        guard let provider = CGDataProvider(dataInfo: nil, data: bytes, size: length, releaseData: unusedCallback) else {
            return
        }

        if let imageRef = CGImage(width: width, height: height, bitsPerComponent: bits, bitsPerPixel: bits * 4, bytesPerRow: bytesInRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: [CGBitmapInfo.byteOrder32Big, CGBitmapInfo(rawValue: blend ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.last.rawValue)],
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        {
            image = UIImage(cgImage: imageRef, scale: scale, orientation: .up)
        }
    }
}

extension Frame: CustomStringConvertible {
    var description: String {
        return "<Frame: \(self.bytes)))> duration: \(self.duration), length: \(length)"
    }
}

extension Frame: CustomDebugStringConvertible {

    var data: Data? {
        if let image = image {
           return UIImagePNGRepresentation(image)
        }
        return nil
    }

    var debugDescription: String {
        return "\(description)\ndata: \(data)"
    }
}
