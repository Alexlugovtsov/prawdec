//
//  Converter.h
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

//@interface TimecodeReader : NSObject
//
//- (void) getFrameRateFromAsset:(AVAsset *)asset
//                    completion:(void (^)(NSString * _Nullable frameRate, NSError * _Nullable error))completion;
//
//@end

@interface PRAWConverter : NSObject

- (void)convertProResRawToDNGWithInputPath:(NSString *)inputPath
                           outputDirectory:(NSString *)outputDirectory
                                //frameCount:(NSInteger)frameCount
                             progressBlock:(void (^)(double progress))progressHandler
                           completionBlock:(void (^)(BOOL success, NSError * _Nullable error))completionHandler;

- (void)cancelConversion;

@end

NS_ASSUME_NONNULL_END
