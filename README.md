# prawdec - ProRes RAW Decoder

Transcodes ProRes RAW to CinemaDNG only for Sony A7S3

## Requirements

- macOS with Xcode (tested on recent versions)
- Command line tools: `xcodebuild`
- [Homebrew](https://brew.sh)
- [libtiff](https://www.libtiff.org/) (install via Homebrew: `brew install libtiff`)

## Build Instructions

1. **Clone the repository**  
   ```sh
   git clone <your-repo-url>
   cd prawdec
   ```

2. **Install dependencies**  
   Make sure `libtiff` is installed:
   ```sh
   brew install libtiff
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
- [ ] Save timecodes to CinemaDNG
- [ ] Extract audio
- [ ] Port to Windows
- [ ] If the ProRes RAW file contains Color Matrices for multiple scenes, use them to calculate more accurate color conversions
- [ ] Use more accurate conversion algorithms
- [ ] Support X-Trans CFA

## Completed
- [x] Support for Bayer CFA
- [x] Use the matrix in metadata to create color conversions for DNG instead of per device maintenance like RAW Converter. This way it can be adapted to any niche or new device. 
- [x] Calibrate the white balance of the converted DNG file. (Assimilate does not calibrate this resulting in single matrix files always being converted to D65)
