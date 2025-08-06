# prawdec - ProRes RAW Decoder
# Does not work on Apple M1, see blelow

Transcodes ProRes RAW to CinemaDNG

based on https://github.com/ArakawaHenri/prawdec project, but uses ColorMatrix from Raw Convertor for some Cameras

Tested and works ONLY on M3 and maybe higher Apple Silicon Processors, because of ```kCVPixelFormatType_16VersatileBayer``` does not work on M1. Cannot Decode from AVFoundationErrorDomain

## Requirements

- macOS with Xcode (tested on recent versions)
- git
- Command line tools: `xcodebuild`
- [Homebrew](https://brew.sh)
- [libtiff](https://www.libtiff.org/)
- [exiftool](https://exiftool.org)

## Build Instructions

1. **Clone the repository**  
   ```sh
   git clone https://github.com/Alexlugovtsov/prawdec.git
   cd prawdec
   ```

2. **Install dependencies**  
   Make sure is installed:
   ```sh
   brew install libtiff
   brew install exiftool
   ```

3. **Open the project in Xcode**  
   ```sh
   open prawdec.xcodeproj
   ```

4. **Configure code signing for local development**  
   - In Xcode, select the project in the Project Navigator.
   - Select the `prawdec` target.
   - Go to the **Signing & Capabilities** tab.
   - Set **Team** to None.
   - Set **Signing Certificate** to "Sign to Run Locally".
   - Make sure "Automatically manage signing" is NOT checked.

5. **Build the app**  
   - In Xcode: Press `Cmd+B` to build.
   - Or from terminal:
     ```sh
     xcodebuild -scheme prawdec
     ```

6. **Run the app locally**  
   - In Xcode: Press `Cmd+R` to run.
   - Or run the built app from the Finder or terminal:
     ```sh
     open ./build/Debug/prawdec.app
     ```

## Notes

- If you do not have a paid Apple Developer account, you can still run the app locally using your free Apple ID as a Personal Team.
- The app will not run on other Macs unless properly signed and notarized.

## Todo
- [x] Save timecodes to CinemaDNG
- [x] Add Framerate of origrnal file
- [ ] Extract audio

##
- Use of Hardcoded Matrix from Raw Convertor, because it is much more accurate for now. data extracted via ```exiftool -b -ColorMatrix1 RawConvertorDNG```

Sony A7S3/FX3
```
ColorMatrix1: 0.7785000205 -0.3873000145 0.07519999892 -0.3670000136 1.073799968 0.33950001 -0.02089999989 0.08810000122 0.7519999743
ColorMatrix2: 0.6912000179 -0.2126999944 -0.04690000042 -0.4469999969 1.217499971 0.2587000132 -0.03979999945 0.1477999985 0.6492000222
```

Sony FX6
```
ColorMatrix1: 1.348080039 -0.331833005 -0.1504119933 -0.3754119873 1.244120002 0.1034779996 -0.05557370186 0.1639209986 0.2404029965
ColorMatrix2: 0.6958900094 -0.1518049985 -0.06731499732 -0.3535940051 1.083709955 0.2317339927 -0.1048979983 0.2441439927 0.5229179859
```

Fujifilm GFX100S II
```
colorMatrix1: 1.5656f, -1.0088f, 0.1263f, -0.2871f,  1.0498f, 0.2752f, 0.0065f,  0.0436f, 0.6714f
colorMatrix2: 1.2806f, -0.5779f, -0.1110f, -0.3546f,  1.1507f,  0.2318f, -0.0177f,  0.0996f,  0.5715f
cameraCalibration1: 1.0661f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.9181f
```
