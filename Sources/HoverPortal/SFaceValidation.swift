import Foundation
import ImageIO
import CoreImage

@MainActor
enum SFaceValidation {
    static func run() {
        var report: [String: Any] = ["result": "failed", "usesCamera": false]
        do {
            let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOVERPORTAL_FACE_FIXTURES"] ?? "")
            func image(_ name: String) throws -> CGImage {
                guard let source=CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL,nil),
                      let image=CGImageSourceCreateImageAtIndex(source,0,nil) else { throw TestError.fixture }
                return image
            }
            let model=try SFaceRecognizer()
            let start=ProcessInfo.processInfo.systemUptime
            let referenceImage=try image("obama.jpg")
            let reference=try model.descriptor(image:referenceImage)
            let identical=try model.descriptor(image:referenceImage)
            let pose=try model.descriptor(image:image("obama2.jpg"))
            let different=try model.descriptor(image:image("biden.jpg"))
            let ci=CIImage(cgImage:referenceImage)
            let dimmed=ci.applyingFilter("CIColorControls",parameters:[kCIInputBrightnessKey:0.04,kCIInputContrastKey:0.75])
            let dimImage=CIContext().createCGImage(dimmed,from:ci.extent)!
            let lighting=try model.descriptor(image:dimImage)
            let profile=OwnerProfile(revision:3,descriptors:Array(repeating:reference,count:24))
            let sameScore=reference.similarity(to:identical), poseScore=reference.similarity(to:pose)
            let otherScore=reference.similarity(to:different), lightingScore=reference.similarity(to:lighting)
            report["identicalScore"]=sameScore; report["differentPhotoSamePersonScore"]=poseScore
            report["differentPersonScore"]=otherScore; report["lightingChangeScore"]=lightingScore
            report["threshold"]=FaceMatcher.threshold
            report["samePersonAccepted"]=FaceMatcher.matches(pose,profiles:profile.descriptors)
            report["differentPersonRejected"] = !FaceMatcher.matches(different,profiles:profile.descriptors)
            report["lightingAccepted"]=FaceMatcher.matches(lighting,profiles:profile.descriptors)
            report["secondsForFiveImages"]=ProcessInfo.processInfo.systemUptime-start
            let passed=profile.valid && sameScore>0.999 && FaceMatcher.matches(pose,profiles:profile.descriptors) &&
                !FaceMatcher.matches(different,profiles:profile.descriptors) && FaceMatcher.matches(lighting,profiles:profile.descriptors)
            report["result"]=passed ? "passed" : "failed"
            report["note"]="Public sample fixtures from face_recognition examples; not a measurement of this user's camera accuracy. Photos are not included in delivery."
        } catch { report["error"]=String(describing:error) }
        let directory=ProcessInfo.processInfo.environment["HOVERPORTAL_UI_REPORT_DIR"] ?? NSTemporaryDirectory()
        if let data=try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]) {
            try? data.write(to:URL(fileURLWithPath:directory).appendingPathComponent("face-model-verification.json"))
            print(String(data:data,encoding:.utf8)!)
        }
    }
    private enum TestError: Error { case fixture }
}
