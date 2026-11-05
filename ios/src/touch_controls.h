// Fight Night Champion iOS - Touch Controls (touch_controls.h)
// Supports Full Spectrum Punch Control (360° Flick Pad) & Classic Xbox 360 layout.

#pragma once

#ifdef __OBJC__
@class UIViewController;
#endif

namespace fnc::touch {

// Puts the touch controls over the game's window. Call on the main thread once
// the game's window exists (FncApp::OnPostSetup). Idempotent.
void Install();

// The FPS counter in the top-left corner:
// frames per second and ms per frame, updated every half second.
void InstallFpsCounter();

#ifdef __OBJC__
// The touch layout editor (positions, sizes, opacity), presented full screen
// in landscape from the launcher or mid-fight gear menu.
UIViewController* MakeLayoutEditor();
#endif

// Set touch boxing style: 0 = Full Spectrum Punch (Flick Pad), 1 = Classic Pad
void SetBoxingStyle(int style);

// Enable/disable straight/jab cardinal calibration corridor
void SetStraightCalibrationEnabled(bool enabled);

}  // namespace fnc::touch
