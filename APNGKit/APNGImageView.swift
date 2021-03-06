//
//  APNGImageView.swift
//  APNGKit
//
//  Created by Wei Wang on 15/8/28.
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

/// An APNG image view object provides a view-based container for displaying an APNG image.
/// You can control the starting and stopping of the animation, as well as the repeat count.
/// All images associated with an APNGImageView object should use the same scale.
/// If your application uses images with different scales, they may render incorrectly.
open class APNGImageView: UIView {

    /// The image displayed in the image view.
    /// If you change the image when the animation playing,
    /// the animation of original image will stop, and the new one will start automatically.
    open var image: APNGImageProtocol? { // Setter should be run on main thread
        didSet {
            let animating = isAnimating
            stopAnimating()

            var firstFrame : SharedFrame?;
            let frameCount = image?.frameCount
            if frameCount != nil && frameCount! > 0 {
                firstFrame = image?.frameAt(index: 0)
            }
            updateContents(frame: firstFrame)
            if animating {
                startAnimating()
            }

            if autoStartAnimation {
                startAnimating()
            }
        }
    }

    /// A Bool value indicating whether the animation is running.
    open fileprivate(set) var isAnimating: Bool

    /// A Bool value indicating whether the animation should be
    /// started automatically after an image is set. Default is false.
    open var autoStartAnimation: Bool {
        didSet {
            if autoStartAnimation {
                startAnimating()
            }
        }
    }

    /// If true runs animation timer with option `NSRunLoopCommonModes`.
    /// ScrollView(CollectionView, TableView) items with Animated APNGImageView will not freeze during scrolling
    /// - Note: This may decrease scrolling smoothness with lot's of animations
    open var allowAnimationInScrollView = false

    var timer: CADisplayLink?
    var lastTimestamp: TimeInterval = 0
    var currentPassedDuration: TimeInterval = 0
    var currentFrameIndex: Int = 0
    var repeated: Int = 0

    /**
    Initialize an APNG image view with the specified image.

    - note: This method adjusts the frame of the receiver to match the
            size of the specified image. It also disables user interactions
            for the image view by default.
            The first frame of image (default image) will be displayed.

    - parameter image: The initial APNG image to display in the image view.

    - returns: An initialized image view object.
    */
    public init(image: APNGImageProtocol?) {
        self.image = image
        isAnimating = false
        autoStartAnimation = false

        if let image = image {
            super.init(frame: CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height))
        } else {
            super.init(frame: CGRect.zero)
        }

        backgroundColor = UIColor.clear
        isUserInteractionEnabled = false
        let firstFrame = (image?.frameCount)! > 0 ? image?.frameAt(index: 0) : nil
        updateContents(frame: firstFrame)
    }

    deinit {
        stopAnimating()
    }

    /**
    Initialize an APNG image view with a decoder.

    - note: You should never call this init method from your code.

    - parameter aDecoder: A decoder used to decode the view from nib.

    - returns: An initialized image view object.
    */
    required public init?(coder aDecoder: NSCoder) {
        isAnimating = false
        autoStartAnimation = false
        super.init(coder: aDecoder)
    }

    /**
    Starts animation contained in the image.
    */
    open func startAnimating() {
        let mainRunLoop = RunLoop.main
        let currentRunLoop = RunLoop.current

        if mainRunLoop != currentRunLoop {
            performSelector(onMainThread: #selector(APNGImageView.startAnimating), with: nil, waitUntilDone: false)
            return
        }

        if isAnimating {
            return
        }

        isAnimating = true
        timer = CADisplayLink.apng_displayLink({ [weak self] (displayLink) -> () in
            self?.tick(displayLink)
        })
        timer?.add(to: mainRunLoop, forMode: (self.allowAnimationInScrollView ? RunLoopMode.commonModes : RunLoopMode.defaultRunLoopMode))
    }

    /**
    Starts animation contained in the image.
    */
    open func stopAnimating() {
        let mainRunLoop = RunLoop.main
        let currentRunLoop = RunLoop.current

        if mainRunLoop != currentRunLoop {
            performSelector(onMainThread: #selector(APNGImageView.stopAnimating), with: nil, waitUntilDone: false)
            return
        }

        if !isAnimating {
            return
        }

        isAnimating = false
        repeated = 0
        lastTimestamp = 0
        currentPassedDuration = 0
        currentFrameIndex = 0

        timer?.invalidate()
        timer = nil
    }

    func tick(_ sender: CADisplayLink?) {

        guard let localTimer = sender,
              let image = image else {
            return
        }

        if lastTimestamp == 0 {
            lastTimestamp = localTimer.timestamp
            return
        }

        let elapsedTime = localTimer.timestamp - lastTimestamp
        lastTimestamp = localTimer.timestamp

        currentPassedDuration += elapsedTime
        let currentFrame = image.frameAt(index: currentFrameIndex)
        let currentFrameDuration = currentFrame.duration

        if currentPassedDuration >= currentFrameDuration {
            currentFrameIndex = currentFrameIndex + 1

            if currentFrameIndex == image.frameCount {
                currentFrameIndex = 0
                repeated = repeated + 1

                if image.repeatCount != RepeatForever && repeated >= image.repeatCount {
                    stopAnimating()
                    // Stop in the last frame
                    return
                }

                // Only the first frame could be hidden.
                if image.firstFrameHidden {
                    currentFrameIndex = 1
                }
            }

            currentPassedDuration = currentPassedDuration - currentFrameDuration
            updateContents(frame: image.frameAt(index: currentFrameIndex))
        }

    }

    var currentFrame: SharedFrame?

    func updateContents(frame: SharedFrame?) {
        currentFrame = frame
        let currentImage: CGImage?
        if layer.contents != nil {
            currentImage = (layer.contents as! CGImage)
        } else {
            currentImage = nil
        }

        let cgImage = frame?.cgImage

        if cgImage !== currentImage {
            layer.contents = cgImage
            if let image = image {
                layer.contentsScale = image.scale
            }

        }

    }
}

private class Block<T> {
    let f : T
    init (_ f: T) { self.f = f }
}

private var apng_userInfoKey: Void?
extension CADisplayLink {

    var apng_userInfo: AnyObject? {
        get {
            return objc_getAssociatedObject(self, &apng_userInfoKey) as AnyObject?
        }
    }

    func apng_setUserInfo(_ userInfo: AnyObject?) {
        objc_setAssociatedObject(self, &apng_userInfoKey, userInfo, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    static func apng_displayLink(_ block: (CADisplayLink) -> ()) -> CADisplayLink
    {
        let displayLink = CADisplayLink(target: self, selector: #selector(CADisplayLink.apng_blockInvoke(_:)))

        let block = Block(block)
        displayLink.apng_setUserInfo(block)
        return displayLink
    }

    static func apng_blockInvoke(_ sender: CADisplayLink) {
        if let block = sender.apng_userInfo as? Block<(CADisplayLink)->()> {
            block.f(sender)
        }
    }

}
