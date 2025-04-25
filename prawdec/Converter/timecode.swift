//import AVFoundation
//import TimecodeKit
//
//@objcMembers
//
//class TimecodeReader: NSObject {
//    public static func getStartCMTine(from asset: AVAsset, completion: @escaping (CMTime?, Error?) -> Void) {
//        Task {
//            do {
//                let startTimecode = try await asset.startTimecode()
//                DispatchQueue.main.async {
//                    completion(startTimecode!.cmTimeValue, nil)
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    completion(nil, error)
//                }
//            }
//        }
//    }
//}
