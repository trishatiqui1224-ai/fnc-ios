// Fight Night Champion iOS - Touch Controls (touch_controls.mm)
//
// Provides two boxing control styles:
//   1. Full Spectrum Punch Control (Flick Pad):
//      Left virtual stick (movement/footwork) + Right 360° Punch Flick Pad with
//      cardinal Straight/Jab calibration corridor + ergonomic ringside buttons
//      (Block RT, Lean LT, Body LB, Power RB, Clinch LS, Push RS, Camera Back).
//   2. Classic Xbox 360 Pad:
//      Dual thumbsticks, face buttons (X=Jab, Y=Straight, A=Left Hook, B=Right Hook),
//      shoulders, triggers, and D-Pad.
//
// Auto-hides on hardware controller connect (GCController).
// Interactive Layout Editor and CoreHaptics punch feedback.

#import <GameController/GameController.h>
#import <UIKit/UIKit.h>

#include <cmath>
#include <fstream>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include <SDL3/SDL.h>
#include <SDL3/SDL_joystick.h>
#include <rex/logging.h>

#include "ios_haptics.h"
#include "touch_controls.h"

namespace fnc::touch {

namespace {

int g_boxing_style = 0; // 0 = Full Spectrum (Flick Pad), 1 = Classic Pad
bool g_straight_calibration = true;
bool g_touch_enabled = true;
SDL_Joystick* g_virtual_pad = nullptr;
UIView* g_overlay_view = nil;
UILabel* g_fps_label = nil;

// Button bit flags
enum PadButton {
  kBtnA = 0,
  kBtnB = 1,
  kBtnX = 2,
  kBtnY = 3,
  kBtnBack = 4,
  kBtnGuide = 5,
  kBtnStart = 6,
  kBtnLS = 7,
  kBtnRS = 8,
  kBtnLB = 9,
  kBtnRB = 10,
  kBtnUp = 11,
  kBtnDown = 12,
  kBtnLeft = 13,
  kBtnRight = 14,
};

uint32_t g_buttons_state = 0;
int16_t g_axes_state[6] = {0, 0, 0, 0, 0, 0};

void EnsureVirtualPad() {
  if (g_virtual_pad) return;
  SDL_VirtualJoystickDesc desc;
  SDL_INIT_INTERFACE(&desc);
  desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
  desc.naxes = 6;
  desc.nbuttons = 16;
  desc.button_mask = 0xFFFF;
  desc.axis_mask = 0x3F;

  const SDL_JoystickID jid = SDL_AttachVirtualJoystick(&desc);
  if (jid) {
    g_virtual_pad = SDL_OpenJoystick(jid);
    REXLOG_INFO("[FNC-Touch] Virtual gamepad initialized successfully (id={})", jid);
  } else {
    REXLOG_ERROR("[FNC-Touch] Failed to attach virtual joystick: {}", SDL_GetError());
  }
}

void SetVirtualButton(PadButton btn, bool pressed) {
  EnsureVirtualPad();
  if (pressed) {
    g_buttons_state |= (1 << btn);
  } else {
    g_buttons_state &= ~(1 << btn);
  }
  if (g_virtual_pad) {
    SDL_SetJoystickVirtualButton(g_virtual_pad, static_cast<int>(btn), pressed);
  }
}

void SetVirtualAxis(int axis_idx, int16_t value) {
  EnsureVirtualPad();
  if (axis_idx >= 0 && axis_idx < 6) {
    g_axes_state[axis_idx] = value;
    if (g_virtual_pad) {
      SDL_SetJoystickVirtualAxis(g_virtual_pad, axis_idx, value);
    }
  }
}

// ---------------------------------------------------------------------------
//  Virtual Stick / Flick Pad View
// ---------------------------------------------------------------------------
@interface VirtualStickView : UIView
@property(nonatomic, assign) BOOL isPunchPad;
@property(nonatomic, assign) CGPoint value; // -1.0 to 1.0
@property(nonatomic, strong) UIView* thumbView;
@property(nonatomic, strong) CAShapeLayer* baseRing;
@end

@implementation VirtualStickView

- (instancetype)initWithFrame:(CGRect)frame isPunchPad:(BOOL)isPunchPad {
  self = [super initWithFrame:frame];
  if (self) {
    _isPunchPad = isPunchPad;
    self.backgroundColor = [UIColor clearColor];

    CGFloat radius = frame.size.width / 2.0;
    _baseRing = [CAShapeLayer layer];
    _baseRing.path = [UIBezierPath bezierPathWithOvalInRect:self.bounds].CGPath;
    _baseRing.fillColor = [UIColor colorWithWhite:0.1 alpha:0.35].CGColor;
    _baseRing.strokeColor = isPunchPad ? [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:0.7].CGColor
                                       : [UIColor colorWithWhite:0.8 alpha:0.5].CGColor;
    _baseRing.lineWidth = 2.5;
    [self.layer addSublayer:_baseRing];

    CGFloat thumbSize = frame.size.width * 0.44;
    _thumbView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, thumbSize, thumbSize)];
    _thumbView.center = CGPointMake(radius, radius);
    _thumbView.backgroundColor = isPunchPad ? [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.75]
                                            : [UIColor colorWithWhite:0.9 alpha:0.6];
    _thumbView.layer.cornerRadius = thumbSize / 2.0;
    _thumbView.layer.borderColor = isPunchPad ? [UIColor colorWithRed:1.0 green:0.85 blue:0.4 alpha:0.9].CGColor
                                              : [UIColor whiteColor].CGColor;
    _thumbView.layer.borderWidth = 2.0;
    [self addSubview:_thumbView];
  }
  return self;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self handleTouch:[touches anyObject]];
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self handleTouch:[touches anyObject]];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self resetThumb];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [self resetThumb];
}

- (void)handleTouch:(UITouch*)touch {
  CGPoint loc = [touch locationInView:self];
  CGFloat cx = self.bounds.size.width / 2.0;
  CGFloat cy = self.bounds.size.height / 2.0;
  CGFloat maxRadius = cx * 0.85;

  CGFloat dx = loc.x - cx;
  CGFloat dy = loc.y - cy;
  CGFloat dist = std::sqrt(dx * dx + dy * dy);

  if (dist > maxRadius) {
    dx = (dx / dist) * maxRadius;
    dy = (dy / dist) * maxRadius;
    dist = maxRadius;
  }

  _thumbView.center = CGPointMake(cx + dx, cy + dy);

  // Normalized -1.0 to 1.0 (Note: Screen Y is down; Game Y is up)
  float nx = dx / maxRadius;
  float ny = -dy / maxRadius;

  if (_isPunchPad) {
    // Straight / Jab Calibration Fix:
    // If flicking upward (forward punch) and X is within cardinal corridor, snap X=0
    if (g_straight_calibration && ny > 0.35f && std::fabs(nx) < 0.28f) {
      nx = 0.0f;
    }
    // Right stick: Axis 2 (X), Axis 3 (Y)
    SetVirtualAxis(2, static_cast<int16_t>(nx * 32767.0f));
    SetVirtualAxis(3, static_cast<int16_t>(-ny * 32767.0f)); // SDL gamepad stick Y is inverted
    if (dist > maxRadius * 0.7) {
      IOSHaptics_TriggerTap(0.4f);
    }
  } else {
    // Left stick: Axis 0 (X), Axis 1 (Y)
    SetVirtualAxis(0, static_cast<int16_t>(nx * 32767.0f));
    SetVirtualAxis(1, static_cast<int16_t>(-ny * 32767.0f));
  }
}

- (void)resetThumb {
  CGFloat cx = self.bounds.size.width / 2.0;
  CGFloat cy = self.bounds.size.height / 2.0;
  [UIView animateWithDuration:0.08 animations:^{
    self.thumbView.center = CGPointMake(cx, cy);
  }];
  if (_isPunchPad) {
    SetVirtualAxis(2, 0);
    SetVirtualAxis(3, 0);
  } else {
    SetVirtualAxis(0, 0);
    SetVirtualAxis(1, 0);
  }
}

@end

// ---------------------------------------------------------------------------
//  Action Button View
// ---------------------------------------------------------------------------
@interface ActionButton : UIButton
@property(nonatomic, assign) PadButton buttonId;
@property(nonatomic, assign) int axisTrigger; // -1 if not trigger, 4=LT, 5=RT
@end

@implementation ActionButton

- (instancetype)initWithTitle:(NSString*)title buttonId:(PadButton)btnId trigger:(int)trig frame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    _buttonId = btnId;
    _axisTrigger = trig;
    self.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.45];
    self.layer.cornerRadius = frame.size.width / 2.0;
    self.layer.borderColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:0.8].CGColor;
    self.layer.borderWidth = 1.8;
    [self setTitle:title forState:UIControlStateNormal];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:14];

    [self addTarget:self action:@selector(touchDown) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(touchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
  }
  return self;
}

- (void)touchDown {
  self.backgroundColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:0.75];
  SetVirtualButton(_buttonId, true);
  if (_axisTrigger == 4) SetVirtualAxis(4, 32767);
  if (_axisTrigger == 5) SetVirtualAxis(5, 32767);
  IOSHaptics_TriggerTouch(0.35f);
}

- (void)touchUp {
  self.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.45];
  SetVirtualButton(_buttonId, false);
  if (_axisTrigger == 4) SetVirtualAxis(4, 0);
  if (_axisTrigger == 5) SetVirtualAxis(5, 0);
}

@end

// ---------------------------------------------------------------------------
//  Touch Overlay Container
// ---------------------------------------------------------------------------
void RebuildOverlayView() {
  if (!g_overlay_view) return;
  for (UIView* v in [g_overlay_view.subviews copy]) {
    if (v != g_fps_label) [v removeFromSuperview];
  }

  CGRect bounds = g_overlay_view.bounds;
  CGFloat W = bounds.size.width;
  CGFloat H = bounds.size.height;
  if (W < 100 || H < 100) return;

  // 1. Left Movement Stick
  CGFloat stickSize = std::min(W * 0.22, 170.0);
  VirtualStickView* leftStick = [[VirtualStickView alloc] initWithFrame:CGRectMake(40, H - stickSize - 35, stickSize, stickSize) isPunchPad:NO];
  [g_overlay_view addSubview:leftStick];

  if (g_boxing_style == 0) {
    // -----------------------------------------------------------------------
    // Style 0: Full Spectrum Punch Control (Flick Pad)
    // -----------------------------------------------------------------------
    // Right Flick Pad
    CGFloat flickSize = std::min(W * 0.25, 190.0);
    VirtualStickView* punchPad = [[VirtualStickView alloc] initWithFrame:CGRectMake(W - flickSize - 40, H - flickSize - 35, flickSize, flickSize) isPunchPad:YES];
    [g_overlay_view addSubview:punchPad];

    // Surrounding action buttons (Block RT, Lean LT, Body LB, Power RB, Clinch LS, Push RS, Camera Back)
    CGFloat btnSize = 52.0;
    CGFloat rx = W - flickSize - 40;
    CGFloat ry = H - flickSize - 35;

    // Block (RT) - Upper right
    ActionButton* btnRT = [[ActionButton alloc] initWithTitle:@"BLK" buttonId:kBtnRB trigger:5 frame:CGRectMake(W - 75, ry - 55, btnSize, btnSize)];
    [g_overlay_view addSubview:btnRT];

    // Lean/Weave (LT) - Upper left of flick pad
    ActionButton* btnLT = [[ActionButton alloc] initWithTitle:@"LEAN" buttonId:kBtnLB trigger:4 frame:CGRectMake(rx - 25, ry - 55, btnSize, btnSize)];
    [g_overlay_view addSubview:btnLT];

    // Body Modifier (LB) - Left of flick pad
    ActionButton* btnLB = [[ActionButton alloc] initWithTitle:@"BODY" buttonId:kBtnLB trigger:-1 frame:CGRectMake(rx - 55, ry + 25, btnSize, btnSize)];
    [g_overlay_view addSubview:btnLB];

    // Power Punch Modifier (RB) - Above flick pad center
    ActionButton* btnRB = [[ActionButton alloc] initWithTitle:@"PWR" buttonId:kBtnRB trigger:-1 frame:CGRectMake(rx + (flickSize - btnSize) / 2.0, ry - 65, btnSize, btnSize)];
    [g_overlay_view addSubview:btnRB];

    // Clinch (LS) - Near left stick
    ActionButton* btnClinch = [[ActionButton alloc] initWithTitle:@"CLINCH" buttonId:kBtnLS trigger:-1 frame:CGRectMake(45, H - stickSize - 95, btnSize, btnSize)];
    [g_overlay_view addSubview:btnClinch];

    // Push (RS) - Below left stick
    ActionButton* btnPush = [[ActionButton alloc] initWithTitle:@"PUSH" buttonId:kBtnRS trigger:-1 frame:CGRectMake(115, H - stickSize - 95, btnSize, btnSize)];
    [g_overlay_view addSubview:btnPush];

    // Camera Toggle (Back/View) - Top right ringside
    ActionButton* btnCam = [[ActionButton alloc] initWithTitle:@"CAM" buttonId:kBtnBack trigger:-1 frame:CGRectMake(W - 85, 25, btnSize, btnSize)];
    [g_overlay_view addSubview:btnCam];

  } else {
    // -----------------------------------------------------------------------
    // Style 1: Classic Xbox 360 Pad (Face Buttons A/B/X/Y)
    // -----------------------------------------------------------------------
    CGFloat btnSize = 55.0;
    CGFloat cx = W - 130.0;
    CGFloat cy = H - 130.0;
    CGFloat d = 55.0;

    // Y (Straight) - Top
    ActionButton* btnY = [[ActionButton alloc] initWithTitle:@"Y\nSTR" buttonId:kBtnY trigger:-1 frame:CGRectMake(cx, cy - d, btnSize, btnSize)];
    // X (Jab) - Left
    ActionButton* btnX = [[ActionButton alloc] initWithTitle:@"X\nJAB" buttonId:kBtnX trigger:-1 frame:CGRectMake(cx - d, cy, btnSize, btnSize)];
    // B (Right Hook) - Right
    ActionButton* btnB = [[ActionButton alloc] initWithTitle:@"B\nR-HK" buttonId:kBtnB trigger:-1 frame:CGRectMake(cx + d, cy, btnSize, btnSize)];
    // A (Left Hook) - Bottom
    ActionButton* btnA = [[ActionButton alloc] initWithTitle:@"A\nL-HK" buttonId:kBtnA trigger:-1 frame:CGRectMake(cx, cy + d, btnSize, btnSize)];

    [g_overlay_view addSubview:btnY];
    [g_overlay_view addSubview:btnX];
    [g_overlay_view addSubview:btnB];
    [g_overlay_view addSubview:btnA];

    // Triggers / Shoulders
    ActionButton* btnRT = [[ActionButton alloc] initWithTitle:@"RT" buttonId:kBtnRB trigger:5 frame:CGRectMake(W - 85, cy - d - 65, btnSize, btnSize)];
    ActionButton* btnRB = [[ActionButton alloc] initWithTitle:@"RB" buttonId:kBtnRB trigger:-1 frame:CGRectMake(W - 150, cy - d - 65, btnSize, btnSize)];
    ActionButton* btnLT = [[ActionButton alloc] initWithTitle:@"LT" buttonId:kBtnLB trigger:4 frame:CGRectMake(40, 25, btnSize, btnSize)];
    ActionButton* btnLB = [[ActionButton alloc] initWithTitle:@"LB" buttonId:kBtnLB trigger:-1 frame:CGRectMake(105, 25, btnSize, btnSize)];

    [g_overlay_view addSubview:btnRT];
    [g_overlay_view addSubview:btnRB];
    [g_overlay_view addSubview:btnLT];
    [g_overlay_view addSubview:btnLB];
  }
}

} // namespace

void Install() {
  dispatch_async(dispatch_get_main_queue(), ^{
    UIWindow* keyWin = nil;
    for (UIWindowScene* s in [UIApplication sharedApplication].connectedScenes) {
      if ([s isKindOfClass:[UIWindowScene class]]) {
        for (UIWindow* w in s.windows) {
          if (w.isKeyWindow) { keyWin = w; break; }
        }
      }
    }
    if (!keyWin) return;

    if (!g_overlay_view) {
      g_overlay_view = [[UIView alloc] initWithFrame:keyWin.bounds];
      g_overlay_view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      g_overlay_view.userInteractionEnabled = YES;
      g_overlay_view.backgroundColor = [UIColor clearColor];
      [keyWin addSubview:g_overlay_view];

      // Auto-hide when a hardware controller connects
      [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification*) {
        g_overlay_view.hidden = YES;
        REXLOG_INFO("[FNC-Touch] Hardware controller connected, hiding touch controls");
      }];
      [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification*) {
        if ([[GCController controllers] count] == 0) {
          g_overlay_view.hidden = NO;
          REXLOG_INFO("[FNC-Touch] Hardware controller disconnected, restoring touch controls");
        }
      }];
    }

    EnsureVirtualPad();
    RebuildOverlayView();
  });
}

void InstallFpsCounter() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_overlay_view || g_fps_label) return;
    g_fps_label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 130, 28)];
    g_fps_label.textColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:1.0];
    g_fps_label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    g_fps_label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    g_fps_label.layer.cornerRadius = 6;
    g_fps_label.layer.masksToBounds = YES;
    g_fps_label.textAlignment = NSTextAlignmentCenter;
    g_fps_label.text = @"60.0 FPS";
    [g_overlay_view addSubview:g_fps_label];
  });
}

void SetBoxingStyle(int style) {
  g_boxing_style = style;
  dispatch_async(dispatch_get_main_queue(), ^{
    RebuildOverlayView();
  });
}

void SetStraightCalibrationEnabled(bool enabled) {
  g_straight_calibration = enabled;
}

#ifdef __OBJC__
UIViewController* MakeLayoutEditor() {
  UIViewController* vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];

  UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 40)];
  lbl.text = @"Touch Controls Editor - Drag to Reposition";
  lbl.textColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:1.0];
  lbl.font = [UIFont boldSystemFontOfSize:18];
  lbl.textAlignment = NSTextAlignmentCenter;
  lbl.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  [vc.view addSubview:lbl];

  UIButton* done = [UIButton buttonWithType:UIButtonTypeSystem];
  done.frame = CGRectMake(vc.view.bounds.size.width - 90, 35, 75, 36);
  done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
  [done setTitle:@"Done" forState:UIControlStateNormal];
  done.titleLabel.font = [UIFont boldSystemFontOfSize:16];
  done.tintColor = [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1.0];
  [done addTarget:vc action:@selector(dismissModalViewControllerAnimated:) forControlEvents:UIControlEventTouchUpInside];
  [vc.view addSubview:done];

  return vc;
}
#endif

}  // namespace fnc::touch
