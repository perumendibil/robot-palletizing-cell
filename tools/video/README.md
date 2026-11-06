# Video editing tools

Scripts used to turn a raw RobotStudio screen recording (*Simulation → Record application*) into
[`media/PalletProject_LinkedIn.mp4`](../../media/PalletProject_LinkedIn.mp4). They are specific to that recording
(crop of the 3D view, time stamps of each scene, position of the markers removed), so treat them as a worked example
rather than a general tool.

## Pipeline

1. **`build_base.py`** (Python 3 + numpy, ffmpeg in `PATH`) builds `base.mp4`, the edited video without captions:
   - crops the 3D view to 16:9 and scales it to 1920 × 1080;
   - re-times the camera orbit to a constant speed, using a 120 fps motion-interpolated copy (ffmpeg `minterpolate`);
   - plays the key moments at ×1 and the filling phases at ×8–×20, with 1.5 s logarithmic speed ramps, frame blending
     in the fast parts and automatic shortening of the robot's vacuum pauses;
   - removes two coordinate-frame markers left in the recording (`_markers.py`, `axes_mask.npy`).
   It also writes `timeline.json` (scene boundaries and speed of every frame).

   It expects in the working folder `src_motion.txt` (per-frame motion of the source, from ffmpeg `tblend` +
   `signalstats`) and `../fin/motion.txt` (the same for the first 40 s).

   ```
   python build_base.py <recording.mp4> <work_folder>
   ```

2. **`remotion/`** ([Remotion](https://www.remotion.dev/) 4, React) adds the captions, the step counter, the speed
   label, the title and the end card on top of `base.mp4`. Copy `base.mp4` to `remotion/public/` and
   `timeline.json` to `remotion/src/`, then:

   ```
   cd remotion
   npm install remotion@4 @remotion/cli@4 react@18.3.1 react-dom@18.3.1
   npx remotion render src/index.ts Main out/video.mp4 --codec=h264 --crf=17
   ```

The camera orbit itself was done in RobotStudio: a smart component with a chain of `MoveToViewpoint` blocks
(12 viewpoints, 30° apart) started by `SimulationEvents.SimulationStarted`.
