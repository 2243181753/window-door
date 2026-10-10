import Foundation
import CoreVideo
import CoreGraphics
import Vision
import FaceRuntime

final class SFaceRecognizer {
    private var model: UnsafeMutableRawPointer
    private var rgb = [UInt8](repeating: 0, count: 112*112*3)
    init() throws {
        let roots = [Bundle.main.resourceURL,
                     URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources")].compactMap { $0 }
        guard let root = roots.first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Models/sface.onnx").path) }) else {
            throw RecognitionError.model("缺少人脸模型")
        }
        var error = [CChar](repeating: 0, count: 1024)
        let pointer = root.appendingPathComponent("Runtime/libonnxruntime.dylib").path.withCString { library in
            root.appendingPathComponent("Models/sface.onnx").path.withCString { path in
                WDCreateFaceModel(library, path, &error, error.count)
            }
        }
        guard let pointer else { throw RecognitionError.model(String(cString: error)) }
        model = pointer
    }
    deinit { WDDestroyFaceModel(model) }

    func descriptor(buffer: CVPixelBuffer, face: VNFaceObservation) throws -> FaceDescriptor {
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let landmarks = face.landmarks, let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let nose = landmarks.noseCrest ?? landmarks.nose, let lips = landmarks.outerLips else { throw RecognitionError.landmarks }
        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map {
                CGPoint(x: (face.boundingBox.minX + CGFloat($0.x) * face.boundingBox.width) * CGFloat(width),
                        y: (1 - face.boundingBox.minY - CGFloat($0.y) * face.boundingBox.height) * CGFloat(height))
            }
        }
        func average(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.map(\.x).reduce(0,+)/CGFloat(points.count), y: points.map(\.y).reduce(0,+)/CGFloat(points.count))
        }
        let eyes = [average(points(leftEye)), average(points(rightEye))].sorted { $0.x < $1.x }
        let nosePoints = points(nose), mouthPoints = points(lips)
        guard let noseTip = nosePoints.max(by: { $0.y < $1.y }),
              let mouthLeft = mouthPoints.min(by: { $0.x < $1.x }), let mouthRight = mouthPoints.max(by: { $0.x < $1.x }),
              eyes[1].x - eyes[0].x > 10 else { throw RecognitionError.landmarks }
        let source = [eyes[0], eyes[1], noseTip, mouthLeft, mouthRight]
        // The five-point 112x112 target is the SFace/OpenCV alignment template.
        let target = [CGPoint(x:38.2946,y:51.6963), CGPoint(x:73.5318,y:51.5014), CGPoint(x:56.0252,y:71.7366),
                      CGPoint(x:41.5493,y:92.3655), CGPoint(x:70.7299,y:92.2041)]
        let sm = average(source), tm = average(target)
        var denominator: CGFloat = 0, aa: CGFloat = 0, bb: CGFloat = 0
        for i in 0..<5 {
            let sx=source[i].x-sm.x, sy=source[i].y-sm.y, tx=target[i].x-tm.x, ty=target[i].y-tm.y
            denominator += sx*sx+sy*sy; aa += sx*tx+sy*ty; bb += sx*ty-sy*tx
        }
        guard denominator > 1 else { throw RecognitionError.landmarks }
        let a=aa/denominator, b=bb/denominator, scale=a*a+b*b
        let tx=tm.x-a*sm.x+b*sm.y, ty=tm.y-b*sm.x-a*sm.y
        guard scale > 0.00001 else { throw RecognitionError.landmarks }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) else { throw RecognitionError.landmarks }
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        rgb.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        for y in 0..<112 { for x in 0..<112 {
            let dx=CGFloat(x)-tx, dy=CGFloat(y)-ty
            let sx=(a*dx+b*dy)/scale, sy=(-b*dx+a*dy)/scale
            let ix=Int(floor(sx)), iy=Int(floor(sy))
            guard ix>=0, iy>=0, ix+1<width, iy+1<height else { continue }
            let fx=Float(sx-CGFloat(ix)), fy=Float(sy-CGFloat(iy))
            for channel in 0..<3 {
                let c=2-channel // BGRA -> RGB, values remain 0...255; ONNX model owns normalization.
                let top=Float(base[iy*stride+ix*4+c])*(1-fx)+Float(base[iy*stride+(ix+1)*4+c])*fx
                let bottom=Float(base[(iy+1)*stride+ix*4+c])*(1-fx)+Float(base[(iy+1)*stride+(ix+1)*4+c])*fx
                rgb[(y*112+x)*3+channel]=UInt8(max(0,min(255,(top*(1-fy)+bottom*fy).rounded())))
            }
        } }
        var embedding = [Float](repeating: 0, count: 512), error = [CChar](repeating: 0, count: 1024)
        let count=rgb.withUnsafeBufferPointer { pixels in
            WDExtractFace(model,pixels.baseAddress,&embedding,embedding.count,&error,error.count)
        }
        guard count == 128 else { throw RecognitionError.model(String(cString:error)) }
        return FaceDescriptor(values: Array(embedding.prefix(Int(count))))
    }
    func descriptor(image: CGImage) throws -> FaceDescriptor {
        var buffer: CVPixelBuffer?
        let status=CVPixelBufferCreate(nil,image.width,image.height,kCVPixelFormatType_32BGRA,
            [kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&buffer)
        guard status==kCVReturnSuccess, let buffer else { throw RecognitionError.landmarks }
        CVPixelBufferLockBaseAddress(buffer, [])
        let context=CGContext(data:CVPixelBufferGetBaseAddress(buffer),width:image.width,height:image.height,
            bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(buffer),space:CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let request=VNDetectFaceLandmarksRequest()
        try VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up).perform([request])
        guard let face=request.results?.max(by: {$0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height}) else { throw RecognitionError.landmarks }
        return try descriptor(buffer:buffer,face:face)
    }
    enum RecognitionError: Error { case landmarks, model(String) }
}
