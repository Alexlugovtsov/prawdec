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
    };
    
    // 计算源和目标白点的LMS值
    float32_t sourceLMS[3];
    float32_t destLMS[3];
    multiplyMatrixVector3(bradford, sourceWhitePoint, sourceLMS);
    multiplyMatrixVector3(bradford, destWhitePoint, destLMS);
    
    // 计算比例因子 (von Kries 假设)
    float32_t rho = destLMS[0] / sourceLMS[0];
    float32_t gamma = destLMS[1] / sourceLMS[1];
    float32_t beta = destLMS[2] / sourceLMS[2];
    
    // 构建对角矩阵 D
    float32_t diagD[9] = {
        rho, 0.0f, 0.0f,
        0.0f, gamma, 0.0f,
        0.0f, 0.0f, beta
    };
    
    // 计算 Bradford 的逆矩阵
    float32_t bradfordInv[9];
    inverseMatrix3x3(bradford, bradfordInv);
    
    // 计算 CAT 矩阵: CAT = BradfordInv * D * Bradford
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
                                //frameCount:(NSInteger)frameCount
                             progressBlock:(void (^)(double))progressHandler
                           completionBlock:(void (^)(BOOL, NSError * _Nullable))completionHandler
{
    // Reset cancellation flag
    self.isCancelled = NO;
    
    // Perform conversion asynchronously on the serial queue
    dispatch_async(self.conversionQueue, ^{
        @autoreleasepool {
            NSError *error = nil;
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:inputPath] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @(YES)}];
            
            AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
            if (error) {
                [self handleCompletionWithSuccess:NO error:error completion:completionHandler];
                return;
            }
            
            NSMutableDictionary *assetMetadataDict = [NSMutableDictionary new];
            
            for (NSString *format in asset.availableMetadataFormats) {
                NSArray<AVMetadataItem *> *items = [asset metadataForFormat:format];
                
                for (AVMetadataItem *item in items) {
                    if (item.key && item.value) {
                        assetMetadataDict[item.key] = item.value ?: [NSNull null];
                    }
                }
            }
            
            NSString *make = assetMetadataDict[@"com.apple.proapps.manufacturer"];
            NSString *model = assetMetadataDict[@"com.apple.proapps.modelname"];
            
            AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
            if (!videoTrack) {
                NSError *trackError = [NSError errorWithDomain:@"ConverterErrorDomain" code:100 userInfo:@{NSLocalizedDescriptionKey: @"No video track found in the asset."}];
                [self handleCompletionWithSuccess:NO error:trackError completion:completionHandler];
                return;
            }
            
            NSDictionary *proResDict = @{
                AVVideoAllowWideColorKey: @(YES),
                (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_16VersatileBayer),
                AVVideoDecompressionPropertiesKey: @{@"EnableLoggingInProResRAW": @(YES)}
            };
            
            AVAssetReaderTrackOutput *videoOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack outputSettings:proResDict];
            videoOutput.alwaysCopiesSampleData = NO;
            
            if (![assetReader canAddOutput:videoOutput]) {
                NSError *outputError = [NSError errorWithDomain:@"ConverterErrorDomain" code:101 userInfo:@{NSLocalizedDescriptionKey: @"Cannot add video output to asset reader."}];
                [self handleCompletionWithSuccess:NO error:outputError completion:completionHandler];
                return;
            }
            
            [assetReader addOutput:videoOutput];
            if (![assetReader startReading]) {
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
            
            while (assetReader.status == AVAssetReaderStatusReading) {
                if (self.isCancelled) {
                    [assetReader cancelReading];
                    NSError *cancelError = [NSError errorWithDomain:@"ConverterErrorDomain" code:107 userInfo:@{NSLocalizedDescriptionKey: @"Conversion was cancelled by the user."}];
                    [self handleCompletionWithSuccess:NO error:cancelError completion:completionHandler];
                    return;
                }
                
                CMSampleBufferRef sampleBuffer = [videoOutput copyNextSampleBuffer];
                if (sampleBuffer) {
                    CVPixelBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                    CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
                    
                    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
                    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
                    size_t width = CVPixelBufferGetWidth(imageBuffer);
                    size_t height = CVPixelBufferGetHeight(imageBuffer);
                    size_t dataLength = bytesPerRow * height;
                    NSData *rawData = [NSData dataWithBytes:baseAddress length:dataLength];
                    
                    // Extract metadata
                    NSDictionary *attributes = (__bridge_transfer NSDictionary *)CVPixelBufferCopyCreationAttributes(imageBuffer);
                    NSNumber *extendedPixelsBottom = attributes[@"ExtendedPixelsBottom"];
                    NSNumber *extendedPixelsLeft = attributes[@"ExtendedPixelsLeft"];
                    NSNumber *extendedPixelsRight = attributes[@"ExtendedPixelsRight"];
                    NSNumber *extendedPixelsTop = attributes[@"ExtendedPixelsTop"];
                    
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
                        
                        NSDictionary *qtMovieTime = attachments[@"QTMovieTime"];
                        NSNumber *qtTimeScale = qtMovieTime[@"TimeScale"];
                        NSNumber *qtTimeValue = qtMovieTime[@"TimeValue"];
                        
                        NSNumber *largestDCQSS = attachments[@"ProResRAW_LargestDCQSS"];
                        NSNumber *fieldCount = attachments[@"CVFieldCount"];
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
                    
                    // Construct output DNG path
                    NSString *outputPath = [self dngPathForInputPath:inputPath frameNumber:currentFrame outputDirectory:outputDirectory];
                    
                    // Create TIFF file
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
                    TIFFSetField(tif, TIFFTAG_SUBFILETYPE, 0);
                    TIFFSetField(tif, TIFFTAG_IMAGEWIDTH, width);
                    TIFFSetField(tif, TIFFTAG_IMAGELENGTH, height);
                    TIFFSetField(tif, TIFFTAG_BITSPERSAMPLE, 16);
                    TIFFSetField(tif, TIFFTAG_SAMPLESPERPIXEL, 1);
                    TIFFSetField(tif, TIFFTAG_COMPRESSION, COMPRESSION_NONE);
                    TIFFSetField(tif, TIFFTAG_PHOTOMETRIC, PHOTOMETRIC_CFA);
                    TIFFSetField(tif, TIFFTAG_ORIENTATION, ORIENTATION_TOPLEFT);
                    TIFFSetField(tif, TIFFTAG_PLANARCONFIG, PLANARCONFIG_CONTIG);
                    TIFFSetField(tif, TIFFTAG_SOFTWARE, "Atomos Ninja V");
                    TIFFSetField(tif, TIFFTAG_DATETIME, [[NSDate date] descriptionWithLocale:nil]);
                    if (make) {
                        TIFFSetField(tif, TIFFTAG_MAKE, [make UTF8String]);
                    }
                    if (model) {
                        TIFFSetField(tif, TIFFTAG_MODEL, [model UTF8String]);
                    }
                                       if (make && model) {
                                           NSString *uniqueModel = [NSString stringWithFormat:@"%@ %@", make, model];
                                           TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, [uniqueModel UTF8String]);
                                       }
                    // TIFFSetField(tif, TIFFTAG_UNIQUECAMERAMODEL, "Blackmagic URSA"); //Fake model for testing ISO
                    
                    uint32_t activeArea[4] = {
                        [extendedPixelsTop unsignedIntValue],
                        [extendedPixelsLeft unsignedIntValue],
                        (uint32_t)height + [extendedPixelsTop unsignedIntValue],
                        (uint32_t)width + [extendedPixelsLeft unsignedIntValue]
                    };
                    TIFFSetField(tif, TIFFTAG_ACTIVEAREA, activeArea);
                    
                    uint8_t version[4] = {1, 4, 0, 0};
                    TIFFSetField(tif, TIFFTAG_DNGVERSION, version);
                    TIFFSetField(tif, TIFFTAG_DNGBACKWARDVERSION, version);
                    
                    // Set CFA Pattern
                    uint8_t cfaPattern[4];
                    int bayerPatternValue = [bayerPattern intValue];
                    
                    switch (bayerPatternValue) {
                        case 1: // GRBG
                            cfaPattern[0] = 1; // Green
                            cfaPattern[1] = 0; // Red
                            cfaPattern[2] = 2; // Blue
                            cfaPattern[3] = 1; // Green
                            break;
                        case 2: // GBRG
                            cfaPattern[0] = 1; // Green
                            cfaPattern[1] = 2; // Blue
                            cfaPattern[2] = 0; // Red
                            cfaPattern[3] = 1; // Green
                            break;
                        case 3: // BGGR
                            cfaPattern[0] = 2; // Blue
                            cfaPattern[1] = 1; // Green
                            cfaPattern[2] = 1; // Green
                            cfaPattern[3] = 0; // Red
                            break;
                        default: // RGGB
                            cfaPattern[0] = 0; // Red
                            cfaPattern[1] = 1; // Green
                            cfaPattern[2] = 1; // Green
                            cfaPattern[3] = 2; // Blue
                            break;
                    }
                    
                    uint16_t cfaPatternDim[2] = {2, 2};
                    TIFFSetField(tif, TIFFTAG_CFAPLANECOLOR, 3, (uint8_t[]){0,1,2});
                    TIFFSetField(tif, TIFFTAG_CFAREPEATPATTERNDIM, cfaPatternDim);
                    TIFFSetField(tif, TIFFTAG_CFAPATTERN, 4, cfaPattern);
                    
                    // Set AsShotNeutral
                    float asShotNeutral[3] = {1.0, 1.0, 1.0};
                    if (whiteBalanceRedFactor && whiteBalanceBlueFactor) {
                        asShotNeutral[0] = 1.0 / [whiteBalanceRedFactor floatValue];
                        asShotNeutral[2] = 1.0 / [whiteBalanceBlueFactor floatValue];
                    }
                    TIFFSetField(tif, TIFFTAG_ASSHOTNEUTRAL, 3, asShotNeutral);
                    
                    if (colorMatrix) {
                        size_t colorMatrixLength = [colorMatrix length];
                        size_t colorMatrixCount = colorMatrixLength / sizeof(float32_t);
                        
                        if (colorMatrixLength % sizeof(float32_t) != 0 || colorMatrixCount != 9) {
                            NSLog(@"Color matrix data length is not a multiple of sizeof(float)");
                            error = [NSError errorWithDomain:@"moe.henri.prawdec" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Invalid color matrix data length"}];
                            TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
                            TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 21);
                        } else {
                            // Create an array to hold the float values
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
                                    TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 21);
                                } else {
                                    for (int col = 0; col < 3; ++col) {
                                        colorMatrix1[col] = invColorMatrix[col] / [whiteBalanceRedFactor doubleValue];
                                        colorMatrix1[3+col] = invColorMatrix[3+col];
                                        colorMatrix1[6+col] = invColorMatrix[6+col] / [whiteBalanceBlueFactor doubleValue];
                                    }
                                }
                                if ([whiteBalanceCCT intValue] != 0) {
                                    float32_t catMatrix[9];
                                    calculateCATMatrixFromCCT([whiteBalanceCCT floatValue], 6504.0f, catMatrix);
                                    float32_t dngColorMatrix1[9];
                                    multiplyMatrix3x3(colorMatrix1, catMatrix, dngColorMatrix1);
                                    
                                    TIFFSetField(tif, TIFFTAG_COLORMATRIX1, colorMatrixCount, dngColorMatrix1);
                                } else {
                                    TIFFSetField(tif, TIFFTAG_COLORMATRIX1, colorMatrixCount, colorMatrix1);
                                }
                                TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 21); //21 For D65 and 17 for SA
                                
                                free(colorMatrixValues);
                            }
                        }
                    } else {
                        TIFFSetField(tif, TIFFTAG_COLORMATRIX1, 9, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 1.0f);
                        TIFFSetField(tif, TIFFTAG_CALIBRATIONILLUMINANT1, 21);
                    }
                    
                    // Set White Level and Black Level
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
                    
                    // Update progress
                    double progress = (double)currentFrame / (double)totalFrames;
                    if (progress > 1.0) progress = 1.0;
                    if (progressHandler) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            progressHandler(progress);
                        });
                    }
                    
                    // Check if reached frameCount
//                    if (frameCount > 0 && currentFrame >= frameCount) {
//                        break;
//                    }
                } else {
                    // No more sample buffers
                    break;
                }
            }
            
            // Check the final status of assetReader
            if (assetReader.status == AVAssetReaderStatusCompleted) {
                [self handleCompletionWithSuccess:YES error:nil completion:completionHandler];
            } else if (self.isCancelled) {
                // Already handled above
            } else {
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
