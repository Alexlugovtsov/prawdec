//
//  Converter.m
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

#import "PRAWConverter.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#include <tiffio.h>

#include <stdint.h>
typedef float float32_t;

@interface PRAWConverter ()
@property (nonatomic, strong) dispatch_queue_t conversionQueue;
@property (nonatomic, assign) BOOL isCancelled;
@end

@implementation PRAWConverter

bool inverseMatrix3x3(const float32_t m[9], float32_t inv[9]) {
    float32_t  det;
    
    inv[0] = m[4] * m[8] - m[5] * m[7];
    inv[1] = m[2] * m[7] - m[1] * m[8];
    inv[2] = m[1] * m[5] - m[2] * m[4];
    inv[3] = m[5] * m[6] - m[3] * m[8];
    inv[4] = m[0] * m[8] - m[2] * m[6];
    inv[5] = m[2] * m[3] - m[0] * m[5];
    inv[6] = m[3] * m[7] - m[4] * m[6];
    inv[7] = m[1] * m[6] - m[0] * m[7];
    inv[8] = m[0] * m[4] - m[1] * m[3];
    
    det = m[0] * inv[0] + m[1] * inv[3] + m[2] * inv[6];
    
    if (det == 0) {
        return false;
    }
    
    det = 1.0 / det;
    
    for (int i = 0; i < 9; i++) {
        inv[i] = inv[i] * det;
    }
    
    return true;
}

void multiplyMatrix3x3(const float32_t a[9], const float32_t b[9], float32_t result[9]) {
    for (int i = 0; i < 3; i++) {
        for (int j = 0; j < 3; j++) {
            result[i * 3 + j] = 0;
            for (int k = 0; k < 3; k++) {
                result[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j];
            }
        }
    }
}

void multiplyMatrixVector3(const float32_t m[9], const float32_t v[3], float32_t result[3]) {
    for (int i = 0; i < 3; i++) {
        result[i] = 0;
        for (int j = 0; j < 3; j++) {
            result[i] += m[i * 3 + j] * v[j];
        }
    }
}

void getWhitePointFromCCT(float32_t cct, float32_t whitePoint[3]) {
    // Approximate xy chromaticity coordinates using McCamy's formula, then convert to XYZ
    float32_t cct2 = cct * cct;
    float32_t cct3 = cct2 * cct;
    float32_t x = 0.0f;
    if (cct >= 1667 && cct <= 4000) {
        x = -0.2661239f * (1e9f / cct3) - 0.2343589f * (1e6f / cct2) + 0.8776956f * (1e3f / cct) + 0.179910f;
    } else if (cct > 4000 && cct <= 25000) {
        x = -3.0258469f * (1e9f / cct3) + 2.1070379f * (1e6f / cct2) + 0.2226347f * (1e3f / cct) + 0.240390f;
    }
    float32_t y = 0.0f;
    if (cct >= 1667 && cct <= 2222) {
        y = -1.1063814f * x * x * x - 1.34811020f * x * x + 2.18555832f * x - 0.20219683f;
    } else if (cct > 2222 && cct <= 4000) {
        y = -0.9549476f * x * x * x - 1.37418593f * x * x + 2.09137015f * x - 0.16748867f;
    } else if (cct > 4000 && cct <= 25000) {
        y = 3.0817580f * x * x * x - 5.8733867f * x * x + 3.75112997f * x - 0.37001483f;
    }
    // Convert to XYZ, assuming Y=1.0
    whitePoint[0] = x / y; // X
    whitePoint[1] = 1.0f;  // Y
    whitePoint[2] = (1.0f - x - y) / y; // Z
}

void calculateCATMatrixFromCCT(float32_t sourceCCT, float32_t destCCT, float32_t catMatrix[9]) {
    // Get source and destination white points
    float32_t sourceWhitePoint[3];
    float32_t destWhitePoint[3];
    getWhitePointFromCCT(sourceCCT, sourceWhitePoint);
    getWhitePointFromCCT(destCCT, destWhitePoint);
    
    // Bradford 变换矩阵 (XYZ to LMS)
    float32_t bradford[9] = {
        0.8951f, 0.2664f, -0.1614f,
        -0.7502f, 1.7135f, 0.0367f,
        0.0389f, -0.0685f, 1.0296f
    }; // Bradford transformation matrix (XYZ to LMS)
    
    // Calculate LMS values for source and destination white points
    float32_t sourceLMS[3];
    float32_t destLMS[3];
    multiplyMatrixVector3(bradford, sourceWhitePoint, sourceLMS);
    multiplyMatrixVector3(bradford, destWhitePoint, destLMS);
    
    // Calculate scaling factors (von Kries hypothesis)
    float32_t rho = destLMS[0] / sourceLMS[0];
    float32_t gamma = destLMS[1] / sourceLMS[1];
    float32_t beta = destLMS[2] / sourceLMS[2];
    
    // Construct diagonal matrix D
    float32_t diagD[9] = {
        rho, 0.0f, 0.0f,
        0.0f, gamma, 0.0f,
        0.0f, 0.0f, beta
    };
    
    // Calculate the inverse of the Bradford matrix
    float32_t bradfordInv[9];
    inverseMatrix3x3(bradford, bradfordInv);
    
    // Calculate CAT matrix: CAT = BradfordInv * D * Bradford
    float32_t temp[9];
    multiplyMatrix3x3(diagD, bradford, temp);
    multiplyMatrix3x3(bradfordInv, temp, catMatrix);
}


- (instancetype)init {
    self = [super init];
    if (self) {
        self.conversionQueue = dispatch_queue_create("moe.henri.prawdec", DISPATCH_QUEUE_SERIAL);
        self.isCancelled = NO;
    }
    return self;
}

- (void)convertProResRawToDNGWithInputPath:(NSString *)inputPath
                           outputDirectory:(NSString *)outputDirectory
                             progressBlock:(void (^)(double))progressHandler
                           completionBlock:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    self.isCancelled = NO;
    NSLog(@"Starting conversion: inputPath=%@, outputDirectory=%@", inputPath, outputDirectory);

    dispatch_async(self.conversionQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            NSLog(@"Loading AVURLAsset...");
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:inputPath] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @(YES)}];

            NSLog(@"Creating AVAssetReader...");
            AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
            if (error) {
                NSLog(@"Error creating AVAssetReader: %@", error);
                [self handleCompletionWithSuccess:NO error:error completion:completionHandler];
                return;
            }

            NSMutableDictionary *assetMetadataDict = [NSMutableDictionary new];
            dispatch_group_t metadataGroup = dispatch_group_create();
            dispatch_queue_t metadataQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);

            NSLog(@"Loading metadata formats...");
            for (NSString *format in asset.availableMetadataFormats) {
                dispatch_group_enter(metadataGroup);
                dispatch_async(metadataQueue, ^{
                    [asset loadMetadataForFormat:format completionHandler:^(NSArray<AVMetadataItem *> *items, NSError * _Nullable metaError) {
                        if (items) {
                            for (AVMetadataItem *item in items) {
                                if (item.key && item.value) {
                                    assetMetadataDict[item.key] = item.value ?: [NSNull null];
                                }
                            }
                        }
                        dispatch_group_leave(metadataGroup);
                    }];
                });
            }
            dispatch_group_wait(metadataGroup, DISPATCH_TIME_FOREVER);

            NSLog(@"Metadata loaded: %@", assetMetadataDict);

            NSString *make = assetMetadataDict[@"com.apple.proapps.manufacturer"];
            NSString *model = assetMetadataDict[@"com.apple.proapps.modelname"];
            NSLog(@"Camera make: %@, model: %@", make, model);

            __block AVAssetTrack *videoTrack = nil;
            dispatch_semaphore_t trackSem = dispatch_semaphore_create(0);
            NSLog(@"Loading video tracks...");
            [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError * _Nullable trackError) {
                videoTrack = tracks.firstObject;
                dispatch_semaphore_signal(trackSem);
            }];
            dispatch_semaphore_wait(trackSem, DISPATCH_TIME_FOREVER);
            if (!videoTrack) {
                NSLog(@"No video track found.");
                NSError *trackError = [NSError errorWithDomain:@"ConverterErrorDomain" code:100 userInfo:@{NSLocalizedDescriptionKey: @"No video track found in the asset."}];
                [self handleCompletionWithSuccess:NO error:trackError completion:completionHandler];
                return;
            }

            NSDictionary *proResDict = @{
                AVVideoAllowWideColorKey: @(YES),
                (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_16VersatileBayer),
                AVVideoDecompressionPropertiesKey: @{@"EnableLoggingInProResRAW": @(YES)}
            };

            NSLog(@"Creating AVAssetReaderTrackOutput...");
            AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:proResDict];
            videoOutput.alwaysCopiesSampleData = NO;

            if (![assetReader canAddOutput:videoOutput]) {
                NSLog(@"Cannot add video output to asset reader.");
                NSError *outputError = [NSError errorWithDomain:@"ConverterErrorDomain" code:101 userInfo:@{NSLocalizedDescriptionKey: @"Cannot add video output to asset reader."}];
                [self handleCompletionWithSuccess:NO error:outputError completion:completionHandler];
                return;
            }

            [assetReader addOutput:videoOutput];
            NSLog(@"Starting asset reading...");
            if (![assetReader startReading]) {
                NSLog(@"Failed to start reading the asset.");
                NSError *startError = assetReader.error ?: [NSError errorWithDomain:@"ConverterErrorDomain" code:102 userInfo:@{NSLocalizedDescriptionKey: @"Failed to start reading the asset."}];
                [self handleCompletionWithSuccess:NO error:startError completion:completionHandler];
                return;
            }
            
            // Estimate total frames
            CMTime duration = asset.duration;
            Float64 durationSeconds = CMTimeGetSeconds(duration);
            NSInteger totalFrames =/* frameCount > 0 ? frameCount :*/ (NSInteger)(videoTrack.nominalFrameRate * durationSeconds);
            if (totalFrames <= 0) {
                totalFrames = 1; // Prevent division by zero
            }
            NSInteger currentFrame = 0;
            NSLog(@"Estimated total frames: %ld", (long)totalFrames);

            while (assetReader.status == AVAssetReaderStatusReading) {
                if (self.isCancelled) {
                    NSLog(@"Conversion cancelled by user.");
                    [assetReader cancelReading];
                    NSError *cancelError = [NSError errorWithDomain:@"ConverterErrorDomain" code:107 userInfo:@{NSLocalizedDescriptionKey: @"Conversion was cancelled by the user."}];
                    [self handleCompletionWithSuccess:NO error:cancelError completion:completionHandler];
                    return;
                }

                CMSampleBufferRef sampleBuffer = [videoOutput copyNextSampleBuffer];
                if (sampleBuffer) {
                    NSLog(@"Processing frame %ld...", (long)currentFrame);

                    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

                    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
                    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
                    size_t width = CVPixelBufferGetWidth(imageBuffer);
                    size_t height = CVPixelBufferGetHeight(imageBuffer);
                    size_t dataLength = bytesPerRow * height;
                    NSData *rawData = [NSData dataWithBytes:baseAddress length:dataLength];

                    NSDictionary *attributes = (__bridge_transfer NSDictionary *)CVPixelBufferCopyCreationAttributes(imageBuffer);

                    NSDictionary *pixelFormatDescription = attributes[@"PixelFormatDescription"];
                    NSString *componentRange = nil;
                    NSNumber *pixelFormat = nil;
                    NSNumber *bitsPerComponent = nil;
                    NSNumber *containsRGB = nil;
                    NSNumber *bitsPerBlock = nil;
                    NSNumber *containsYCbCr = nil;
                    NSNumber *containsGrayscale = nil;
                    NSNumber *containsAlpha = nil;
                    NSNumber *containsSenselArray = nil;
                    
                    if ([pixelFormatDescription isKindOfClass:[NSDictionary class]]) {
                        componentRange = pixelFormatDescription[@"ComponentRange"];
                        pixelFormat = pixelFormatDescription[@"PixelFormat"];
                        bitsPerComponent = pixelFormatDescription[@"BitsPerComponent"];
                        containsRGB = pixelFormatDescription[@"ContainsRGB"];
                        bitsPerBlock = pixelFormatDescription[@"BitsPerBlock"];
                        containsYCbCr = pixelFormatDescription[@"ContainsYCbCr"];
                        containsGrayscale = pixelFormatDescription[@"ContainsGrayscale"];
                        containsAlpha = pixelFormatDescription[@"ContainsAlpha"];
                        containsSenselArray = pixelFormatDescription[@"ContainsSenselArray"];
                    }

                    NSDictionary *attachments = (__bridge_transfer NSDictionary *)CVBufferCopyAttachments(imageBuffer, kCVAttachmentMode_ShouldPropagate);
                    NSNumber *whiteBalanceCCT = nil;
                    NSData *metadataExtension = nil;
                    NSData *recommendedCrop = nil;
                    NSNumber *whiteBalanceBlueFactor = nil;
                    NSNumber *blackLevel = nil;
                    NSData *colorMatrix = nil;
                    NSNumber *whiteLevel = nil;
                    NSNumber *bayerPattern = nil;
                    NSNumber *gainFactor = nil;
                    NSNumber *whiteBalanceRedFactor = nil;
                    NSNumber *horizontalSpacing = nil;
                    NSNumber *verticalSpacing = nil;
                    NSString *transferFunction = nil;
                    
                    if (attachments) {
                        whiteBalanceCCT = attachments[@"ProResRAW_WhiteBalanceCCT"];
                        metadataExtension = attachments[@"ProResRAW_MetadataExtension"];
                        recommendedCrop = attachments[@"ProResRAW_RecommendedCrop"];
                        
//                        NSDictionary *qtMovieTime = attachments[@"QTMovieTime"];
//                        NSNumber *qtTimeScale = qtMovieTime[@"TimeScale"];
//                        NSNumber *qtTimeValue = qtMovieTime[@"TimeValue"];
//                        
//                        NSNumber *largestDCQSS = attachments[@"ProResRAW_LargestDCQSS"];
//                        NSNumber *fieldCount = attachments[@"CVFieldCount"];
                        whiteBalanceBlueFactor = attachments[@"ProResRAW_WhiteBalanceBlueFactor"];
                        blackLevel = attachments[@"ProResRAW_BlackLevel"];
                        colorMatrix = attachments[@"ProResRAW_ColorMatrix"];
                        whiteLevel = attachments[@"ProResRAW_WhiteLevel"];
                        bayerPattern = attachments[@"ProResRAW_BayerPattern"];
                        gainFactor = attachments[@"ProResRAW_GainFactor"];
                        whiteBalanceRedFactor = attachments[@"ProResRAW_WhiteBalanceRedFactor"];
                        
                        NSDictionary *pixelAspectRatio = attachments[@"CVPixelAspectRatio"];
                        horizontalSpacing = pixelAspectRatio[@"HorizontalSpacing"];
                        verticalSpacing = pixelAspectRatio[@"VerticalSpacing"];
                        
                        transferFunction = attachments[@"CVImageBufferTransferFunction"];
                    }

                    NSString *outputPath = [self dngPathForInputPath:inputPath frameNumber:currentFrame outputDirectory:outputDirectory];
                    NSLog(@"Creating TIFF file at path: %@", outputPath);

                    TIFF *tif = TIFFOpen([outputPath UTF8String], "w");
                    if (!tif) {
                        NSLog(@"Failed to open TIFF file at path: %@", outputPath);
                        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                        CFRelease(sampleBuffer);
                        NSError *tiffError = [NSError errorWithDomain:@"ConverterErrorDomain" code:103 userInfo:@{NSLocalizedDescriptionKey: @"Failed to open TIFF file for writing."}];
                        [self handleCompletionWithSuccess:NO error:tiffError completion:completionHandler];
                        return;
                    }

                    // Set TIFF fields
                    NSLog(@"Setting TIFF fields...");
                    TIFFSetField(tif, TIFFTAG_SUBFILETYPE, 0);
                    TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, width);
                    TIFFSetField(tif, TIFFTAG_IMAGELENGTH, height);
                    TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, 16);
                    TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 1);
                    TIFFSetField(tif, TIFFTAG_ROWSPERSTRIP, height);
                    TIFFSetField(tif, TIFFTAG_XRESOLUTION, 96.0f);     // 96 dpi horizontal
                    TIFFSetField(tif, TIFFTAG_YRESOLUTION, 96.0f);     // 96 dpi vertical
                    TIFFSetField(tif, TIFFTAG_RESOLUTIONUNIT, 2);      // 2 = inches
                    TIFFSetField(tif, TIFFTAG_COMPRESSION, COMPRESSION_NONE);
                    TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_CFA);
                    TIFFSetField(tif, TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT);
                    TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
                    TIFFSetField(tif, TIFFTAG_SOFTWARE, "Atomos Ninja V");
                    // TIFFSetField(tif, TIFFTAG_DATETIME, [[NSDate date] descriptionWithLocale:nil]);

                    if (make) {
                        if ([make caseInsensitiveCompare:@"Sony"] == NSOrderedSame) {
                            make = @"SONY";
                        }
                        NSString *uniqueMake = [NSString stringWithFormat:@"%@", make];
                        TIFFSetField(tif, TIFFTAG_MAKE, [uniqueMake UTF8String]);
                    }
                    if (model) {
                        TIFFSetField(tif, TIFFTAG_MODEL, [model UTF8String]);
                    }
                    if (make && model) {
                        if ([make caseInsensitiveCompare:@"Sony"] == NSOrderedSame) {
                            make = @"SONY";
                        }
                        else if ([make caseInsensitiveCompare:@"Fujifilm"] == NSOrderedSame) {
                            make = @"FUJIFILM";
                        }
                        NSString *uniqueModel = [NSString stringWithFormat:@"%@ %@", make, model];
                        TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, [uniqueModel UTF8String]);
                    }
                    // TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, "Blackmagic URSA"); //Fake model for testing ISO
                    // TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, "Panasonic ICLE-7SM3"); //Fake model for testing Color !perfect!
                    
                    // uint32_t activeArea[4] = {
                    //     [extendedPixelsTop unsignedIntValue],
                    //     [extendedPixelsLeft unsignedIntValue],
                    //     (uint32_t)height + [extendedPixelsTop unsignedIntValue],
                    //     (uint32_t)width + [extendedPixelsLeft unsignedIntValue]
                    // };
                    // TIFFSetField(tif, TIFFTAG_ACTIVEAREA, activeArea);
                    
                    uint8_t version[4] = {1, 4, 0, 0};
                    TIFFSetField(tif, TIFFTAG_DNGVERSION, version);
                    // TIFFSetField(tif, TIFFTAG_DNGBACKWARDVERSION, version);
                    
                    // Set CFA Pattern
                    uint8_t cfaPattern[4];
                    int bayerPatternValue = [bayerPattern intValue];
                    switch (bayerPatternValue) {
                        case 1: cfaPattern[0] = 1; cfaPattern[1] = 0; cfaPattern[2] = 2; cfaPattern[3] = 1; break;
                        case 2: cfaPattern[0] = 1; cfaPattern[1] = 2; cfaPattern[2] = 0; cfaPattern[3] = 1; break;
                        case 3: cfaPattern[0] = 2; cfaPattern[1] = 1; cfaPattern[2] = 1; cfaPattern[3] = 0; break;
                        default: cfaPattern[0] = 0; cfaPattern[1] = 1; cfaPattern[2] = 1; cfaPattern[3] = 2; break;
                    }
                    uint16_t cfaPatternDim[2] = {2, 2};
                    TIFFSetField(tif, TIFFTAG_CFAREPEATPATTERNDIM, cfaPatternDim);
                    TIFFSetField(tif, TIFFTAG_CFAPATTERN, 4, cfaPattern);

                    float asShotNeutral[3] = {1.0, 1.0, 1.0};
                    if (whiteBalanceRedFactor && whiteBalanceBlueFactor) {
                        asShotNeutral[0] = 1.0 / [whiteBalanceRedFactor floatValue];
                        asShotNeutral[2] = 1.0 / [whiteBalanceBlueFactor floatValue];
                    }
                    TIFFSetField(tif, TIFFTAG_ASSHOTNEUTRAL, 3, asShotNeutral);

                    // Sony A7S3 Start
                    if ([model isEqualToString:@"ILCE-7SM3"]) {
                        NSLog(@"Applying Sony A7S3 color matrices and calibration...");
                        float32_t colorMatrix1[] = {
                            0.7785f, -0.3873f, 0.0752f,
                            -0.3670f,  1.0738f,  0.3395f,
                            -0.0209f,  0.0881f,  0.7520f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, colorMatrix1);

                        float32_t colorMatrix2[] = {
                            0.6912f, -0.2127f, -0.0469f,
                            -0.4470f,  1.2175f,  0.2587f,
                            -0.0398f,  0.1478f,  0.6492f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX2, 9, colorMatrix2);

                        float32_t cameraCalibration1[] = {
                            1.0546f, 0.0f, 0.0f,
                            0.0f, 1.0f, 0.0f,
                            0.0f, 0.0f, 0.9980999827f
                        };
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION1, 9, cameraCalibration1);
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION2, 9, cameraCalibration1);
                    }
                    // Sony A7S3 End
                    // Sony FX3 Start
                    else if ([model isEqualToString:@"ILME-FX3"]) {
                        NSLog(@"Applying Sony FX3 color matrices and calibration...");
                        float32_t colorMatrix1[] = {
                            0.7785f, -0.3873f, 0.0752f,
                            -0.3670f,  1.0738f,  0.3395f,
                            -0.0209f,  0.0881f,  0.7520f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, colorMatrix1);

                        float32_t colorMatrix2[] = {
                            0.6912f, -0.2127f, -0.0469f,
                            -0.4470f,  1.2175f,  0.2587f,
                            -0.0398f,  0.1478f,  0.6492f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX2, 9, colorMatrix2);

                        float32_t cameraCalibration1[] = {
                            1.0546f, 0.0f, 0.0f,
                            0.0f, 1.0f, 0.0f,
                            0.0f, 0.0f, 0.9980999827f
                        };
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION1, 9, cameraCalibration1);
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION2, 9, cameraCalibration1);
                    }
                    // Sony FX3 End
                    // Sony FX6 Start
                    else if ([model isEqualToString:@"ILME-FX6V"]) {
                        NSLog(@"Applying Sony FX6V color matrices and calibration...");
                        float32_t colorMatrix1[] = {
                            1.3481f, -0.3318f, -0.1504f,
                           -0.3754f,  1.2441f,  0.1035f,
                           -0.0556f,  0.1639f,  0.2404f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, colorMatrix1);

                        float32_t colorMatrix2[] = {
                            0.6959f, -0.1518f, -0.0673f,
                           -0.3536f,  1.0837f,  0.2317f,
                           -0.1049f,  0.2441f,  0.5229f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX2, 9, colorMatrix2);

                        float32_t cameraCalibration1[] = {
                            1.0f, 0.0f, 0.0f,
                            0.0f, 1.0f, 0.0f,
                            0.0f, 0.0f, 1.0f
                        };
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION1, 9, cameraCalibration1);
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION2, 9, cameraCalibration1);
                    }
                    // Sony FX6 End
                    // Sony GFX100S II Start
                    else if ([model isEqualToString:@"GFX100S II"]) {
                        NSLog(@"Applying Sony GFX100S II color matrices and calibration...");
                        float32_t colorMatrix1[] = {
                            1.5656f, -1.0088f, 0.1263f,
                            -0.2871f,  1.0498f, 0.2752f,
                             0.0065f,  0.0436f, 0.6714f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, colorMatrix1);

                        float32_t colorMatrix2[] = {
                            1.2806f, -0.5779f, -0.1110f,
                            -0.3546f,  1.1507f,  0.2318f,
                            -0.0177f,  0.0996f,  0.5715f
                        };
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX2, 9, colorMatrix2);

                        float32_t cameraCalibration1[] = {
                            1.0661f, 0.0f, 0.0f,
                            0.0f, 1.0f, 0.0f,
                            0.0f, 0.0f, 0.9181f
                        };
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION1, 9, cameraCalibration1);
                        TIFFSetField(tif, TIFFTAG_CAMERACALIBRATION2, 9, cameraCalibration1);
                    }
                    // Sony GFX100S II End
                    else {
                        if (colorMatrix) {
                            NSLog(@"Processing Matrix Based on WB Calculations...");
                            NSLog(@"Original ColorMatrix: %f %f %f %f %f %f %f %f %f",
                                ((float32_t*)[colorMatrix bytes])[0],
                                ((float32_t*)[colorMatrix bytes])[1],
                                ((float32_t*)[colorMatrix bytes])[2],
                                ((float32_t*)[colorMatrix bytes])[3],
                                ((float32_t*)[colorMatrix bytes])[4],
                                ((float32_t*)[colorMatrix bytes])[5],
                                ((float32_t*)[colorMatrix bytes])[6],
                                ((float32_t*)[colorMatrix bytes])[7],
                                ((float32_t*)[colorMatrix bytes])[8]);
                            size_t colorMatrixLength = [colorMatrix length];
                            size_t colorMatrixCount = colorMatrixLength / sizeof(float32_t);

                            if (colorMatrixLength % sizeof(float32_t) != 0 || colorMatrixCount != 9) {
                                NSLog(@"Color matrix data length is not a multiple of sizeof(float)");
                                error = [NSError errorWithDomain:@"moe.henri.prawdec" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid color matrix data length"}];
                                TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
                                TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 17);
                                TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, 21);
                            } else {
                                float32_t *colorMatrixValues = (float32_t*)malloc(colorMatrixLength);
                                if (colorMatrixValues == NULL) {
                                    NSLog(@"Failed to allocate memory for color matrix");
                                    error = [NSError errorWithDomain:@"com.example.dngwriter" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Memory allocation failure"}];
                                } else {
                                    [colorMatrix getBytes:colorMatrixValues length:colorMatrixLength];

                                    float32_t invColorMatrix[9];
                                    float32_t colorMatrix1[9];

                                    if (!inverseMatrix3x3(colorMatrixValues, invColorMatrix)) {
                                        NSLog(@"Color matrix is not invertible");
                                        error = [NSError errorWithDomain:@"moe.henri.prawdec" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Color matrix inversion failed"}];
                                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
                                        TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 17);
                                        TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, 21);
                                    } else {
                                        NSLog(@"Color matrix is invertible");
                                        for (int col = 0; col < 3; ++col) {
                                            colorMatrix1[col] = invColorMatrix[col] / [whiteBalanceRedFactor doubleValue];
                                            colorMatrix1[3+col] = invColorMatrix[3+col];
                                            colorMatrix1[6+col] = invColorMatrix[6+col] / [whiteBalanceBlueFactor doubleValue];
                                        }
                                    }
                                    NSLog(@"ColorMatrix1 before WB: %f %f %f %f %f %f %f %f %f",
                                        colorMatrix1[0], colorMatrix1[1], colorMatrix1[2],
                                        colorMatrix1[3], colorMatrix1[4], colorMatrix1[5],
                                        colorMatrix1[6], colorMatrix1[7], colorMatrix1[8]);
                                    if ([whiteBalanceCCT intValue] != 0) {
                                        NSLog(@"WB is set, applying Color Adaptation Matrix");
                                        NSLog(@"whiteBalanceCCT = %@", whiteBalanceCCT);
                                        float32_t catMatrix[9];
                                        calculateCATMatrixFromCCT([whiteBalanceCCT floatValue], 6504.0f, catMatrix);
                                        float32_t dngColorMatrix1[9];
                                        multiplyMatrix3x3(colorMatrix1, catMatrix, dngColorMatrix1);

                                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, colorMatrixCount, dngColorMatrix1);
                                    } else {
                                        NSLog(@"WB not set, using original color matrix");
                                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, colorMatrixCount, colorMatrix1);
                                    }
                                    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 17);
                                    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, 21);

                                    free(colorMatrixValues);
                                }
                            }
                        } else {
                            NSLog(@"No color matrix provided, using default D65 matrix");
                            TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
                            TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 17);
                            TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, 21);
                        }
                    }

                    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 17);
                    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT2, 21);

                    uint32_t _whiteLevel = [whiteLevel unsignedIntValue];
                    float _blackLevel = [blackLevel floatValue];
                    TIFFSetField(tif, TIFFTAG_WHITELEVEL, 1, &_whiteLevel);
                    TIFFSetField(tif, TIFFTAG_BLACKLEVEL, 1, &_blackLevel);
                    // Set Baseline Exposure
                    float32_t baselineExposure = log2([gainFactor floatValue]);
                    TIFFSetField(tif, TIFFTAG_BASELINEEXPOSURE, baselineExposure);
                    
                    // Write image data
                    const uint8_t *pixels = (const uint8_t *)[rawData bytes];
                    for (uint32_t row = 0; row < height; ++row) {
                        if (self.isCancelled) {
                            NSLog(@"Conversion cancelled during writing scanlines.");
                            TIFFClose(tif);
                            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                            CFRelease(sampleBuffer);
                            NSError *cancelError = [NSError errorWithDomain:@"ConverterErrorDomain" code:107 userInfo:@{NSLocalizedDescriptionKey: @"Conversion was cancelled by the user."}];
                            [self handleCompletionWithSuccess:NO error:cancelError completion:completionHandler];
                            return;
                        }

                        const uint8_t *rowData = pixels + (row * bytesPerRow);
                        if (TIFFWriteScanline(tif, (void *)rowData, row, 0) < 0) {
                            NSLog(@"Failed to write scanline %u", row);
                            TIFFClose(tif);
                            CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                            CFRelease(sampleBuffer);
                            NSError *writeError = [NSError errorWithDomain:@"ConverterErrorDomain" code:104 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write scanline to TIFF file."}];
                            [self handleCompletionWithSuccess:NO error:writeError completion:completionHandler];
                            return;
                        }
                    }
                    
                    // Finalize TIFF file
                    if (!TIFFWriteDirectory(tif)) {
                        NSLog(@"Failed to write TIFF directory.");
                        TIFFClose(tif);
                        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                        CFRelease(sampleBuffer);
                        NSError *dirError = [NSError errorWithDomain:@"ConverterErrorDomain" code:105 userInfo:@{NSLocalizedDescriptionKey: @"Failed to write TIFF directory."}];
                        [self handleCompletionWithSuccess:NO error:dirError completion:completionHandler];
                        return;
                    }

                    TIFFClose(tif);
                    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
                    CFRelease(sampleBuffer);

                    currentFrame++;
                    double progress = (double)currentFrame / (double)totalFrames;
                    if (progress > 1.0) progress = 1.0;
                    if (progressHandler) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            NSLog(@"Progress updated: %.2f%%", progress * 100);
                            progressHandler(progress);
                        });
                    }
                } else {
                    NSLog(@"No more sample buffers.");
                    break;
                }
            }

            NSLog(@"Conversion finished. Checking assetReader status...");
            if (assetReader.status == AVAssetReaderStatusCompleted) {
                NSLog(@"Conversion completed successfully.");
                [self handleCompletionWithSuccess:YES error:nil completion:completionHandler];
            } else if (self.isCancelled) {
                NSLog(@"Conversion was cancelled.");
            } else {
                NSLog(@"Asset reader did not complete successfully.");
                NSError *finalError = assetReader.error ?: [NSError errorWithDomain:@"ConverterErrorDomain" code:106 userInfo:@{NSLocalizedDescriptionKey: @"Asset reader did not complete successfully."}];
                [self handleCompletionWithSuccess:NO error:finalError completion:completionHandler];
            }
        }
    });
}

- (void)cancelConversion {
    self.isCancelled = YES;
}

- (NSString *)dngPathForInputPath:(NSString *)inputPath frameNumber:(NSInteger)frameNumber outputDirectory:(NSString *)outputDirectory {
    NSString *inputFilename = [inputPath lastPathComponent];
    NSString *baseName = [inputFilename stringByDeletingPathExtension];
    NSString *dngFilename = [NSString stringWithFormat:@"%@_%09ld.dng", baseName, (long)frameNumber];
    return [outputDirectory stringByAppendingPathComponent:dngFilename];
}

- (void)handleCompletionWithSuccess:(BOOL)success error:(NSError * _Nullable)error completion:(void (^)(BOOL, NSError * _Nullable))completionHandler {
    if (completionHandler) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(success, error);
        });
    }
}

@end
