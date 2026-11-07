// Fight Night Champion iOS - Touch Controls (touch_controls.mm)
//
// Overhauled Glassmorphic Virtual Controller with Dual Ring Mode & Menu Navigation Mode,
// Full Spectrum Punch Control (FSPC) Right Stick Velocity Gating & Corridor Calibration,
// Direct Touch / Swipe Navigation, and CoreHaptics Feedback.

#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>

#include <cmath>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include <SDL3/SDL.h>
#include <SDL3/SDL_joystick.h>
#include <rex/logging.h>

#include "ios_haptics.h"
#include "touch_controls.h"

namespace {

// Virtual Controller State
static SDL_Joystick* g_virtual_pad = nullptr;
static UIView* g_overlay_container = nil;
static UILabel* g_fps_label = nil;
static bool g_straight_calibration = true;
static int g_boxing_style = 0; // 0 = Full Spectrum (Flick Pad), 1 = Classic Pad

// SDL Gamepad Button Indices
enum FNCButtonIndex : int {
  kFNCButtonA          = 0,
  kFNCButtonB          = 1,
  kFNCButtonX          = 2,
  kFNCButtonY          = 3,
  kFNCButtonBack       = 4,
  kFNCButtonGuide      = 5,
  kFNCButtonStart      = 6,
  kFNCButtonLStick     = 7,
  kFNCButtonRStick     = 8,
  kFNCButtonLB         = 9,
  kFNCButtonRB         = 10,
  kFNCButtonDPadUp     = 11,
  kFNCButtonDPadDown   = 12,
  kFNCButtonDPadLeft   = 13,
  kFNCButtonDPadRight  = 14,
};

// SDL Gamepad Axes
enum FNCAxisIndex : int {
  kFNCAxisLeftX        = 0,
  kFNCAxisLeftY        = 1,
  kFNCAxisRightX       = 2,
  kFNCAxisRightY       = 3,
  kFNCAxisTriggerLeft  = 4,
  kFNCAxisTriggerRight = 5,
};

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

}  // namespace

extern "C" SDL_Joystick* FNC_GetVirtualJoystick(void) {
  EnsureVirtualPad();
  return g_virtual_pad;
}

static inline void FNC_SendButton(int button, bool pressed) {
  EnsureVirtualPad();
  if (g_virtual_pad && button >= 0) {
    SDL_SetJoystickVirtualButton(g_virtual_pad, button, pressed);
  }
}

static inline void FNC_SendAxis(int axis, Sint16 value) {
  EnsureVirtualPad();
  if (g_virtual_pad && axis >= 0 && axis < 6) {
    SDL_SetJoystickVirtualAxis(g_virtual_pad, axis, value);
  }
}

#pragma mark - Glassmorphic Button View

@interface FNCGlassButton : UIControl
@property(nonatomic, copy) NSString* titleText;
@property(nonatomic, copy) NSString* subtitleText;
@property(nonatomic, strong) UIColor* accentColor;
@property(nonatomic, assign) int sdlButton;
@property(nonatomic, assign) int sdlTriggerAxis;
@property(nonatomic, assign) BOOL isPill;
@end

@implementation FNCGlassButton {
  UIVisualEffectView* _blurView;
  UILabel* _titleLabel;
  UILabel* _subLabel;
  CAShapeLayer* _ringLayer;
  UIImpactFeedbackGenerator* _haptic;
}

- (instancetype)initWithTitle:(NSString*)title
                     subtitle:(NSString*)subtitle
                  accentColor:(UIColor*)accent
                    sdlButton:(int)btn
                  triggerAxis:(int)axis
                       isPill:(BOOL)isPill {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _titleText = [title copy];
    _subtitleText = [subtitle copy];
    _accentColor = accent ?: [UIColor colorWithWhite:0.9 alpha:1.0];
    _sdlButton = btn;
    _sdlTriggerAxis = axis;
    _isPill = isPill;
    _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [_haptic prepare];

    self.multipleTouchEnabled = YES;
    self.backgroundColor = [UIColor clearColor];

    UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    _blurView.userInteractionEnabled = NO;
    _blurView.clipsToBounds = YES;
    _blurView.alpha = 0.78;
    [self addSubview:_blurView];

    _ringLayer = [CAShapeLayer layer];
    _ringLayer.fillColor = [UIColor colorWithWhite:0.08 alpha:0.35].CGColor;
    _ringLayer.strokeColor = [_accentColor colorWithAlphaComponent:0.65].CGColor;
    _ringLayer.lineWidth = 1.6;
    [self.layer addSublayer:_ringLayer];

    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = _titleText;
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.font = [UIFont systemFontOfSize:(isPill ? 11.0 : 15.0) weight:UIFontWeightHeavy];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];

    if (_subtitleText.length > 0) {
      _subLabel = [[UILabel alloc] init];
      _subLabel.text = _subtitleText;
      _subLabel.textColor = [_accentColor colorWithAlphaComponent:0.9];
      _subLabel.font = [UIFont systemFontOfSize:8.0 weight:UIFontWeightBold];
      _subLabel.textAlignment = NSTextAlignmentCenter;
      [self addSubview:_subLabel];
    }
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat radius = _isPill ? (self.bounds.size.height * 0.5)
                           : (MIN(self.bounds.size.width, self.bounds.size.height) * 0.5);
  _blurView.frame = self.bounds;
  _blurView.layer.cornerRadius = radius;

  UIBezierPath* path = [UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds, 1.0, 1.0)
                                                  cornerRadius:radius - 1.0];
  _ringLayer.path = path.CGPath;
  _ringLayer.frame = self.bounds;

  if (_subLabel) {
    _titleLabel.frame = CGRectMake(0, 4, self.bounds.size.width, self.bounds.size.height * 0.58);
    _subLabel.frame = CGRectMake(0, self.bounds.size.height * 0.56, self.bounds.size.width, 12);
  } else {
    _titleLabel.frame = self.bounds;
  }
}

- (void)setPressedState:(BOOL)pressed {
  if (pressed) {
    [_haptic impactOccurred];
    if (_sdlTriggerAxis >= 0) {
      FNC_SendAxis(_sdlTriggerAxis, 32767);
    } else if (_sdlButton >= 0) {
      FNC_SendButton(_sdlButton, true);
    }
    [UIView animateWithDuration:0.06 animations:^{
      self.transform = CGAffineTransformMakeScale(0.91, 0.91);
      self->_ringLayer.fillColor = [self->_accentColor colorWithAlphaComponent:0.45].CGColor;
      self->_ringLayer.strokeColor = self->_accentColor.CGColor;
      self->_ringLayer.lineWidth = 2.4;
    }];
  } else {
    if (_sdlTriggerAxis >= 0) {
      FNC_SendAxis(_sdlTriggerAxis, 0);
    } else if (_sdlButton >= 0) {
      FNC_SendButton(_sdlButton, false);
    }
    [UIView animateWithDuration:0.12 animations:^{
      self.transform = CGAffineTransformIdentity;
      self->_ringLayer.fillColor = [UIColor colorWithWhite:0.08 alpha:0.35].CGColor;
      self->_ringLayer.strokeColor = [self->_accentColor colorWithAlphaComponent:0.65].CGColor;
      self->_ringLayer.lineWidth = 1.6;
    }];
  }
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [super touchesBegan:touches withEvent:event];
  [self setPressedState:YES];
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [super touchesEnded:touches withEvent:event];
  [self setPressedState:NO];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  [super touchesCancelled:touches withEvent:event];
  [self setPressedState:NO];
}

@end

#pragma mark - Analog Thumbstick View (Footwork & Full Spectrum Punch Control)

@interface FNCThumbstickView : UIView
@property(nonatomic, assign) int axisX;
@property(nonatomic, assign) int axisY;
@property(nonatomic, assign) int stickClickButton;
@property(nonatomic, copy) NSString* labelTitle;
@property(nonatomic, strong) UIColor* themeColor;
@property(nonatomic, assign) BOOL isFspcPunchStick;
@end

@implementation FNCThumbstickView {
  UIVisualEffectView* _baseBlur;
  CAShapeLayer* _baseRing;
  UIView* _knobView;
  UILabel* _label;
  UITouch* _activeTouch;
  NSTimeInterval _lastTapTime;
  UIImpactFeedbackGenerator* _edgeHaptic;
  BOOL _wasAtRim;
}

- (instancetype)initWithTitle:(NSString*)title
                        axisX:(int)axX
                        axisY:(int)axY
                  clickButton:(int)clickBtn
                   themeColor:(UIColor*)color
                 isPunchStick:(BOOL)isPunch {
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _labelTitle = [title copy];
    _axisX = axX;
    _axisY = axY;
    _stickClickButton = clickBtn;
    _themeColor = color;
    _isFspcPunchStick = isPunch;
    _edgeHaptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleRigid];
    self.multipleTouchEnabled = YES;

    UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    _baseBlur = [[UIVisualEffectView alloc] initWithEffect:blur];
    _baseBlur.userInteractionEnabled = NO;
    _baseBlur.alpha = 0.55;
    _baseBlur.clipsToBounds = YES;
    [self addSubview:_baseBlur];

    _baseRing = [CAShapeLayer layer];
    _baseRing.fillColor = [UIColor clearColor].CGColor;
    _baseRing.strokeColor = [_themeColor colorWithAlphaComponent:0.45].CGColor;
    _baseRing.lineWidth = 2.0;
    _baseRing.lineDashPattern = @[@6, @4];
    [self.layer addSublayer:_baseRing];

    _knobView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    _knobView.backgroundColor = [_themeColor colorWithAlphaComponent:0.35];
    _knobView.layer.cornerRadius = 28;
    _knobView.layer.borderColor = [_themeColor colorWithAlphaComponent:0.9].CGColor;
    _knobView.layer.borderWidth = 2.2;
    _knobView.userInteractionEnabled = NO;
    [self addSubview:_knobView];

    _label = [[UILabel alloc] init];
    _label.text = _labelTitle;
    _label.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    _label.font = [UIFont systemFontOfSize:9.0 weight:UIFontWeightHeavy];
    _label.textAlignment = NSTextAlignmentCenter;
    [_knobView addSubview:_label];
  }
  return self;
}

- (void)layoutSubviews {
  [super layoutSubviews];
  CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) * 0.5;
  _baseBlur.frame = self.bounds;
  _baseBlur.layer.cornerRadius = r;
  _baseRing.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(self.bounds, 2, 2)].CGPath;
  if (!_activeTouch) {
    _knobView.center = CGPointMake(self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
  }
  _label.frame = _knobView.bounds;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
  return CGRectContainsPoint(CGRectInset(self.bounds, -15, -15), point);
}

- (void)updateWithTouch:(UITouch*)touch {
  CGPoint center = CGPointMake(self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
  CGPoint pt = [touch locationInView:self];
  CGFloat dx = pt.x - center.x;
  CGFloat dy = pt.y - center.y;
  CGFloat maxRadius = (MIN(self.bounds.size.width, self.bounds.size.height) * 0.5) - 18.0;
  if (maxRadius < 15.0) maxRadius = 45.0;
  CGFloat dist = std::hypot(dx, dy);

  if (dist > maxRadius && dist > 0.0001f) {
    dx = (dx / dist) * maxRadius;
    dy = (dy / dist) * maxRadius;
    dist = maxRadius;
    if (!_wasAtRim) {
      [_edgeHaptic impactOccurredWithIntensity:0.65];
      _wasAtRim = YES;
    }
  } else {
    _wasAtRim = NO;
  }

  _knobView.center = CGPointMake(center.x + dx, center.y + dy);

  float deadzone = _isFspcPunchStick ? 0.15f : 0.12f;
  float rawMag = (float)(dist / maxRadius);
  float scaledMag = 0.0f;
  if (rawMag > deadzone) {
    scaledMag = (rawMag - deadzone) / (1.0f - deadzone);
    if (scaledMag > 1.0f) scaledMag = 1.0f;
  }

  float dirX = (dist > 0.0001f) ? (float)(dx / dist) : 0.0f;
  float dirY = (dist > 0.0001f) ? (float)(dy / dist) : 0.0f;

  float normX = dirX * scaledMag;
  float normY = dirY * scaledMag;

  // Fight Night Champion Full Spectrum Punch Control (FSPC) Tuning
  if (_isFspcPunchStick && g_straight_calibration && scaledMag > 0.001f) {
    float angleRad = std::atan2(normY, normX);
    float angleDeg = angleRad * (180.0f / 3.14159265f);
    float deltaFromTop = std::fmod(angleDeg - (-90.0f) + 360.0f, 360.0f);
    if (deltaFromTop > 180.0f) deltaFromTop -= 360.0f;

    // Jab / Straight corridor: -24 to +24 deg from 12 o'clock
    if (std::fabs(deltaFromTop) <= 24.0f) {
      normX = 0.0f;
      normY = -scaledMag; // Pure upward snap for crisp Straight/Jab
    }
    // Right Hook: +90 deg (3 o'clock)
    else if (std::fabs(deltaFromTop - 90.0f) <= 20.0f) {
      normX = scaledMag;
      normY = 0.0f;
    }
    // Left Hook: -90 deg (9 o'clock)
    else if (std::fabs(deltaFromTop - (-90.0f)) <= 20.0f) {
      normX = -scaledMag;
      normY = 0.0f;
    }
    // Right Uppercut: +145 deg (5 o'clock)
    else if (std::fabs(deltaFromTop - 145.0f) <= 18.0f) {
      normX = scaledMag * 0.82f;
      normY = scaledMag * 0.57f;
    }
    // Left Uppercut: -145 deg (7 o'clock)
    else if (std::fabs(deltaFromTop - (-145.0f)) <= 18.0f) {
      normX = -scaledMag * 0.82f;
      normY = scaledMag * 0.57f;
    }
  }

  FNC_SendAxis(_axisX, (Sint16)std::round(normX * 32767.0f));
  FNC_SendAxis(_axisY, (Sint16)std::round(normY * 32767.0f));
}

- (void)resetStick {
  _activeTouch = nil;
  _wasAtRim = NO;
  FNC_SendAxis(_axisX, 0);
  FNC_SendAxis(_axisY, 0);
  FNC_SendButton(_stickClickButton, false);
  [UIView animateWithDuration:0.14
                        delay:0
       usingSpringWithDamping:0.65
        initialSpringVelocity:0.5
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    self->_knobView.center = CGPointMake(self.bounds.size.width * 0.5, self.bounds.size.height * 0.5);
    self->_knobView.transform = CGAffineTransformIdentity;
  } completion:nil];
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if (!_activeTouch) {
    _activeTouch = [touches anyObject];
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    // Double-tap stick for L3 / R3 click
    if (now - _lastTapTime < 0.28) {
      FNC_SendButton(_stickClickButton, true);
    }
    _lastTapTime = now;
    [UIView animateWithDuration:0.08 animations:^{
      self->_knobView.transform = CGAffineTransformMakeScale(1.12, 1.12);
    }];
    [self updateWithTouch:_activeTouch];
  }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if ([touches containsObject:_activeTouch]) {
    [self updateWithTouch:_activeTouch];
  }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if ([touches containsObject:_activeTouch]) {
    [self resetStick];
  }
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event {
  if ([touches containsObject:_activeTouch]) {
    [self resetStick];
  }
}

@end

#pragma mark - Main Overlay Container (Menu Nav + Ring Controls)

@interface FNCVirtualControllerOverlay : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, assign) BOOL menuNavigationMode;
@end

@implementation FNCVirtualControllerOverlay {
  // Left & Right Analog Sticks
  FNCThumbstickView* _leftStick;
  FNCThumbstickView* _rightStick;

  // D-Pad for Main Menu & In-Fight Adjustments
  UIView* _dpadContainer;
  FNCGlassButton* _dpadUp;
  FNCGlassButton* _dpadDown;
  FNCGlassButton* _dpadLeft;
  FNCGlassButton* _dpadRight;

  // Face Buttons (A, B, X, Y)
  FNCGlassButton* _btnA;
  FNCGlassButton* _btnB;
  FNCGlassButton* _btnX;
  FNCGlassButton* _btnY;

  // Bumpers & Triggers (Block, Lean, Body, Power/Haymaker)
  FNCGlassButton* _btnLB;
  FNCGlassButton* _btnRB;
  FNCGlassButton* _btnLT;
  FNCGlassButton* _btnRT;

  // Top Navigation Bar (BACK, START, NAV MODE, HUD OPACITY)
  FNCGlassButton* _btnBack;
  FNCGlassButton* _btnStart;
  UIButton* _btnModeToggle;
  UIButton* _btnOpacityToggle;
  UILabel* _modeBannerLabel;

  // Center Touchpad Swipe Recognizer for fast Main Menu navigation
  UISwipeGestureRecognizer* _swipeUp;
  UISwipeGestureRecognizer* _swipeDown;
  UISwipeGestureRecognizer* _swipeLeft;
  UISwipeGestureRecognizer* _swipeRight;
  UITapGestureRecognizer* _doubleTapConfirm;

  CGFloat _hudAlpha;
}

- (instancetype)initWithFrame:(CGRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    self.multipleTouchEnabled = YES;
    self.backgroundColor = [UIColor clearColor];
    _hudAlpha = 0.90;
    _menuNavigationMode = NO;

    [self buildControls];
    [self setupMenuSwipeGestures];
  }
  return self;
}

- (void)buildControls {
  UIColor* goldColor    = [UIColor colorWithRed:0.96 green:0.78 blue:0.26 alpha:1.0];
  UIColor* crimsonColor = [UIColor colorWithRed:0.92 green:0.22 blue:0.26 alpha:1.0];
  UIColor* greenColor   = [UIColor colorWithRed:0.24 green:0.86 blue:0.42 alpha:1.0];
  UIColor* blueColor    = [UIColor colorWithRed:0.26 green:0.62 blue:0.98 alpha:1.0];
  UIColor* steelColor   = [UIColor colorWithRed:0.78 green:0.82 blue:0.88 alpha:1.0];

  // 1. Analog Sticks
  _leftStick = [[FNCThumbstickView alloc] initWithTitle:@"MOVE"
                                                  axisX:kFNCAxisLeftX
                                                  axisY:kFNCAxisLeftY
                                            clickButton:kFNCButtonLStick
                                             themeColor:steelColor
                                           isPunchStick:NO];
  [self addSubview:_leftStick];

  _rightStick = [[FNCThumbstickView alloc] initWithTitle:@"PUNCH"
                                                   axisX:kFNCAxisRightX
                                                   axisY:kFNCAxisRightY
                                             clickButton:kFNCButtonRStick
                                              themeColor:crimsonColor
                                            isPunchStick:YES];
  [self addSubview:_rightStick];

  // 2. Cross D-Pad (Essential for Main Menu & Fight Night Navigation)
  _dpadContainer = [[UIView alloc] initWithFrame:CGRectZero];
  [self addSubview:_dpadContainer];

  _dpadUp    = [[FNCGlassButton alloc] initWithTitle:@"▲" subtitle:nil accentColor:goldColor sdlButton:kFNCButtonDPadUp    triggerAxis:-1 isPill:NO];
  _dpadDown  = [[FNCGlassButton alloc] initWithTitle:@"▼" subtitle:nil accentColor:goldColor sdlButton:kFNCButtonDPadDown  triggerAxis:-1 isPill:NO];
  _dpadLeft  = [[FNCGlassButton alloc] initWithTitle:@"◄" subtitle:nil accentColor:goldColor sdlButton:kFNCButtonDPadLeft  triggerAxis:-1 isPill:NO];
  _dpadRight = [[FNCGlassButton alloc] initWithTitle:@"►" subtitle:nil accentColor:goldColor sdlButton:kFNCButtonDPadRight triggerAxis:-1 isPill:NO];
  [_dpadContainer addSubview:_dpadUp];
  [_dpadContainer addSubview:_dpadDown];
  [_dpadContainer addSubview:_dpadLeft];
  [_dpadContainer addSubview:_dpadRight];

  // 3. Face Buttons (A=Confirm, B=Back, X, Y)
  _btnA = [[FNCGlassButton alloc] initWithTitle:@"A" subtitle:@"OK"   accentColor:greenColor   sdlButton:kFNCButtonA triggerAxis:-1 isPill:NO];
  _btnB = [[FNCGlassButton alloc] initWithTitle:@"B" subtitle:@"BACK" accentColor:crimsonColor sdlButton:kFNCButtonB triggerAxis:-1 isPill:NO];
  _btnX = [[FNCGlassButton alloc] initWithTitle:@"X" subtitle:nil     accentColor:blueColor    sdlButton:kFNCButtonX triggerAxis:-1 isPill:NO];
  _btnY = [[FNCGlassButton alloc] initWithTitle:@"Y" subtitle:nil     accentColor:goldColor    sdlButton:kFNCButtonY triggerAxis:-1 isPill:NO];
  [self addSubview:_btnA];
  [self addSubview:_btnB];
  [self addSubview:_btnX];
  [self addSubview:_btnY];

  // 4. Triggers & Bumpers (Labeled for Fight Night Champion mechanics)
  _btnLT = [[FNCGlassButton alloc] initWithTitle:@"LT" subtitle:@"BODY/LEAN" accentColor:steelColor   sdlButton:-1           triggerAxis:kFNCAxisTriggerLeft  isPill:YES];
  _btnLB = [[FNCGlassButton alloc] initWithTitle:@"LB" subtitle:@"WEAVE/TAB" accentColor:steelColor   sdlButton:kFNCButtonLB triggerAxis:-1                   isPill:YES];
  _btnRT = [[FNCGlassButton alloc] initWithTitle:@"RT" subtitle:@"BLOCK"     accentColor:goldColor    sdlButton:-1           triggerAxis:kFNCAxisTriggerRight isPill:YES];
  _btnRB = [[FNCGlassButton alloc] initWithTitle:@"RB" subtitle:@"POWER/TAB" accentColor:crimsonColor sdlButton:kFNCButtonRB triggerAxis:-1                   isPill:YES];
  [self addSubview:_btnLT];
  [self addSubview:_btnLB];
  [self addSubview:_btnRT];
  [self addSubview:_btnRB];

  // 5. Top Navigation Bar (BACK, START, Mode Switch, Opacity)
  _btnBack  = [[FNCGlassButton alloc] initWithTitle:@"BACK"  subtitle:nil accentColor:steelColor sdlButton:kFNCButtonBack  triggerAxis:-1 isPill:YES];
  _btnStart = [[FNCGlassButton alloc] initWithTitle:@"START" subtitle:nil accentColor:goldColor  sdlButton:kFNCButtonStart triggerAxis:-1 isPill:YES];
  [self addSubview:_btnBack];
  [self addSubview:_btnStart];

  _btnModeToggle = [UIButton buttonWithType:UIButtonTypeSystem];
  [_btnModeToggle setTitle:@"🥊 RING MODE" forState:UIControlStateNormal];
  [_btnModeToggle setTitleColor:goldColor forState:UIControlStateNormal];
  _btnModeToggle.titleLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightHeavy];
  _btnModeToggle.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.65];
  _btnModeToggle.layer.cornerRadius = 14.0;
  _btnModeToggle.layer.borderWidth = 1.2;
  _btnModeToggle.layer.borderColor = [goldColor colorWithAlphaComponent:0.6].CGColor;
  [_btnModeToggle addTarget:self action:@selector(toggleNavigationMode) forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:_btnModeToggle];

  _btnOpacityToggle = [UIButton buttonWithType:UIButtonTypeSystem];
  [_btnOpacityToggle setTitle:@"👁" forState:UIControlStateNormal];
  [_btnOpacityToggle setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
  _btnOpacityToggle.titleLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightBold];
  _btnOpacityToggle.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.65];
  _btnOpacityToggle.layer.cornerRadius = 14.0;
  _btnOpacityToggle.layer.borderWidth = 1.0;
  _btnOpacityToggle.layer.borderColor = [UIColor colorWithWhite:0.6 alpha:0.4].CGColor;
  [_btnOpacityToggle addTarget:self action:@selector(cycleOpacity) forControlEvents:UIControlEventTouchUpInside];
  [self addSubview:_btnOpacityToggle];

  _modeBannerLabel = [[UILabel alloc] init];
  _modeBannerLabel.text = @"SWIPE CENTER TO NAVIGATE MENU • DOUBLE-TAP TO SELECT (A)";
  _modeBannerLabel.textColor = [goldColor colorWithAlphaComponent:0.85];
  _modeBannerLabel.font = [UIFont systemFontOfSize:10.0 weight:UIFontWeightBold];
  _modeBannerLabel.textAlignment = NSTextAlignmentCenter;
  _modeBannerLabel.alpha = 0.0;
  [self addSubview:_modeBannerLabel];
}

#pragma mark - Direct Touch / Swipe Menu Navigation

- (void)setupMenuSwipeGestures {
  auto addSwipe = ^(UISwipeGestureRecognizerDirection dir, SEL action) {
    UISwipeGestureRecognizer* swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:action];
    swipe.direction = dir;
    swipe.cancelsTouchesInView = NO;
    swipe.delaysTouchesBegan = NO;
    swipe.delegate = self;
    [self addGestureRecognizer:swipe];
    return swipe;
  };
  _swipeUp    = addSwipe(UISwipeGestureRecognizerDirectionUp,    @selector(handleSwipeUp));
  _swipeDown  = addSwipe(UISwipeGestureRecognizerDirectionDown,  @selector(handleSwipeDown));
  _swipeLeft  = addSwipe(UISwipeGestureRecognizerDirectionLeft,  @selector(handleSwipeLeft));
  _swipeRight = addSwipe(UISwipeGestureRecognizerDirectionRight, @selector(handleSwipeRight));

  _doubleTapConfirm = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTapConfirm)];
  _doubleTapConfirm.numberOfTapsRequired = 2;
  _doubleTapConfirm.cancelsTouchesInView = NO;
  _doubleTapConfirm.delaysTouchesBegan = NO;
  _doubleTapConfirm.delegate = self;
  [self addGestureRecognizer:_doubleTapConfirm];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
  if (!_menuNavigationMode) {
    return NO;
  }
  CGPoint p = [touch locationInView:self];
  if (CGRectContainsPoint(_leftStick.frame, p) ||
      CGRectContainsPoint(_rightStick.frame, p) ||
      CGRectContainsPoint(_dpadContainer.frame, p) ||
      CGRectContainsPoint(_btnA.frame, p) ||
      CGRectContainsPoint(_btnB.frame, p) ||
      CGRectContainsPoint(_btnX.frame, p) ||
      CGRectContainsPoint(_btnY.frame, p) ||
      CGRectContainsPoint(_btnLT.frame, p) ||
      CGRectContainsPoint(_btnLB.frame, p) ||
      CGRectContainsPoint(_btnRT.frame, p) ||
      CGRectContainsPoint(_btnRB.frame, p) ||
      CGRectContainsPoint(_btnBack.frame, p) ||
      CGRectContainsPoint(_btnStart.frame, p) ||
      CGRectContainsPoint(_btnModeToggle.frame, p) ||
      CGRectContainsPoint(_btnOpacityToggle.frame, p)) {
    return NO;
  }
  return YES;
}

- (void)pulseButton:(int)sdlBtn {
  UIImpactFeedbackGenerator* gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
  [gen impactOccurred];
  FNC_SendButton(sdlBtn, true);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(75 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
    FNC_SendButton(sdlBtn, false);
  });
}

- (void)handleSwipeUp    { if (_menuNavigationMode) [self pulseButton:kFNCButtonDPadUp]; }
- (void)handleSwipeDown  { if (_menuNavigationMode) [self pulseButton:kFNCButtonDPadDown]; }
- (void)handleSwipeLeft  { if (_menuNavigationMode) [self pulseButton:kFNCButtonDPadLeft]; }
- (void)handleSwipeRight { if (_menuNavigationMode) [self pulseButton:kFNCButtonDPadRight]; }
- (void)handleDoubleTapConfirm { if (_menuNavigationMode) [self pulseButton:kFNCButtonA]; }

- (void)toggleNavigationMode {
  _menuNavigationMode = !_menuNavigationMode;
  UIImpactFeedbackGenerator* gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
  [gen impactOccurred];

  UIColor* goldColor = [UIColor colorWithRed:0.96 green:0.78 blue:0.26 alpha:1.0];
  UIColor* cyanColor = [UIColor colorWithRed:0.28 green:0.84 blue:0.98 alpha:1.0];

  if (_menuNavigationMode) {
    [_btnModeToggle setTitle:@"📋 MENU NAV" forState:UIControlStateNormal];
    [_btnModeToggle setTitleColor:cyanColor forState:UIControlStateNormal];
    _btnModeToggle.layer.borderColor = cyanColor.CGColor;
  } else {
    [_btnModeToggle setTitle:@"🥊 RING MODE" forState:UIControlStateNormal];
    [_btnModeToggle setTitleColor:goldColor forState:UIControlStateNormal];
    _btnModeToggle.layer.borderColor = [goldColor colorWithAlphaComponent:0.6].CGColor;
  }

  [UIView animateWithDuration:0.22
                        delay:0
       usingSpringWithDamping:0.78
        initialSpringVelocity:0.4
                      options:UIViewAnimationOptionBeginFromCurrentState
                   animations:^{
    self->_modeBannerLabel.alpha = self->_menuNavigationMode ? 1.0 : 0.0;
    self->_rightStick.alpha = self->_menuNavigationMode ? 0.20 : self->_hudAlpha;
    self->_btnLT.alpha = self->_menuNavigationMode ? 0.20 : self->_hudAlpha;
    self->_btnRT.alpha = self->_menuNavigationMode ? 0.20 : self->_hudAlpha;
    [self setNeedsLayout];
    [self layoutIfNeeded];
  } completion:nil];
}

- (void)cycleOpacity {
  if (_hudAlpha > 0.8f) _hudAlpha = 0.55f;
  else if (_hudAlpha > 0.4f) _hudAlpha = 0.22f;
  else _hudAlpha = 0.90f;

  [UIView animateWithDuration:0.18 animations:^{
    for (UIView* sub in self.subviews) {
      if (sub != self->_btnModeToggle && sub != self->_btnOpacityToggle && sub != self->_modeBannerLabel) {
        sub.alpha = self->_hudAlpha;
      }
    }
  }];
}

#pragma mark - Responsive Ergonomic Layout (874x402 Landscape Safe Area)

- (void)layoutSubviews {
  [super layoutSubviews];
  UIEdgeInsets safe = self.safeAreaInsets;
  CGFloat W = self.bounds.size.width;
  CGFloat H = self.bounds.size.height;
  CGFloat leftPad  = MAX(safe.left, 18.0);
  CGFloat rightPad = MAX(safe.right, 18.0);
  CGFloat topPad   = MAX(safe.top, 12.0);
  CGFloat botPad   = MAX(safe.bottom, 14.0);

  // Top Center Navigation Bar
  CGFloat centerX = W * 0.5;
  _btnModeToggle.frame    = CGRectMake(centerX - 58, topPad, 116, 28);
  _btnBack.frame          = CGRectMake(centerX - 132, topPad, 66, 28);
  _btnStart.frame         = CGRectMake(centerX + 66, topPad, 66, 28);
  _btnOpacityToggle.frame = CGRectMake(centerX + 140, topPad, 34, 28);
  _modeBannerLabel.frame  = CGRectMake(centerX - 200, topPad + 32, 400, 16);

  // Left & Right Shoulder Triggers / Bumpers
  CGFloat shW = 78.0, shH = 34.0;
  _btnLT.frame = CGRectMake(leftPad, topPad + 4, shW, shH);
  _btnLB.frame = CGRectMake(leftPad + shW + 10, topPad + 4, shW, shH);

  _btnRT.frame = CGRectMake(W - rightPad - shW, topPad + 4, shW, shH);
  _btnRB.frame = CGRectMake(W - rightPad - (shW * 2) - 10, topPad + 4, shW, shH);

  if (_menuNavigationMode) {
    // MENU NAVIGATION MODE: Prominent Left D-Pad + Large Right Action Cluster
    CGFloat dpadSize = 148.0;
    _dpadContainer.frame = CGRectMake(leftPad + 16, H - botPad - dpadSize - 24, dpadSize, dpadSize);
    _leftStick.frame = CGRectMake(leftPad + dpadSize + 34, H - botPad - 110, 100, 100);

    CGFloat bSize = 54.0;
    CGFloat clusterX = W - rightPad - 100;
    CGFloat clusterY = H - botPad - 106;
    _btnA.frame = CGRectMake(clusterX - bSize*0.5, clusterY + 34, bSize, bSize);
    _btnB.frame = CGRectMake(clusterX + 36,        clusterY - bSize*0.5, bSize, bSize);
    _btnX.frame = CGRectMake(clusterX - 36 - bSize,clusterY - bSize*0.5, bSize, bSize);
    _btnY.frame = CGRectMake(clusterX - bSize*0.5, clusterY - 34 - bSize, bSize, bSize);

    _rightStick.frame = CGRectMake(W - rightPad - 235, H - botPad - 96, 86, 86);
  } else {
    // RING BOXING MODE: Ergonomic Dual Analog Sticks (Left = Footwork, Right = Full Spectrum Punch)
    CGFloat stickSize = 142.0;
    _leftStick.frame  = CGRectMake(leftPad + 8, H - botPad - stickSize - 8, stickSize, stickSize);
    _rightStick.frame = CGRectMake(W - rightPad - stickSize - 8, H - botPad - stickSize - 8, stickSize, stickSize);

    // Compact D-Pad tucked above-right of Left Stick for quick menu/corner access
    CGFloat dpadSize = 104.0;
    _dpadContainer.frame = CGRectMake(leftPad + stickSize + 18, H - botPad - dpadSize - 12, dpadSize, dpadSize);

    // Compact Diamond Action Cluster arched around Right Stick
    CGFloat bSize = 42.0;
    CGFloat clusterX = W - rightPad - stickSize - 74;
    CGFloat clusterY = H - botPad - 76;
    _btnA.frame = CGRectMake(clusterX - bSize*0.5, clusterY + 26, bSize, bSize);
    _btnB.frame = CGRectMake(clusterX + 28,        clusterY - bSize*0.5, bSize, bSize);
    _btnX.frame = CGRectMake(clusterX - 28 - bSize,clusterY - bSize*0.5, bSize, bSize);
    _btnY.frame = CGRectMake(clusterX - bSize*0.5, clusterY - 26 - bSize, bSize, bSize);
  }

  // Layout D-Pad Buttons inside _dpadContainer
  CGFloat dW = _dpadContainer.bounds.size.width;
  CGFloat dH = _dpadContainer.bounds.size.height;
  CGFloat btnS = dW * 0.34;
  _dpadUp.frame    = CGRectMake((dW - btnS)*0.5, 0,          btnS, btnS);
  _dpadDown.frame  = CGRectMake((dW - btnS)*0.5, dH - btnS,  btnS, btnS);
  _dpadLeft.frame  = CGRectMake(0,               (dH - btnS)*0.5, btnS, btnS);
  _dpadRight.frame = CGRectMake(dW - btnS,       (dH - btnS)*0.5, btnS, btnS);
}

@end

#pragma mark - Public API (fnc::touch)

namespace fnc::touch {

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

    if (!g_overlay_container) {
      g_overlay_container = [[FNCVirtualControllerOverlay alloc] initWithFrame:keyWin.bounds];
      g_overlay_container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      g_overlay_container.userInteractionEnabled = YES;
      [keyWin addSubview:g_overlay_container];

      // Auto-hide when a hardware controller connects
      [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidConnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification*) {
        g_overlay_container.hidden = YES;
        REXLOG_INFO("[FNC-Touch] Hardware controller connected, hiding touch controls");
      }];
      [[NSNotificationCenter defaultCenter] addObserverForName:GCControllerDidDisconnectNotification
                                                        object:nil
                                                         queue:[NSOperationQueue mainQueue]
                                                    usingBlock:^(NSNotification*) {
        if ([[GCController controllers] count] == 0) {
          g_overlay_container.hidden = NO;
          REXLOG_INFO("[FNC-Touch] Hardware controller disconnected, restoring touch controls");
        }
      }];
    }

    EnsureVirtualPad();
  });
}

void InstallFpsCounter() {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_overlay_container || g_fps_label) return;
    g_fps_label = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, 130, 28)];
    g_fps_label.textColor = [UIColor colorWithRed:0.83 green:0.68 blue:0.21 alpha:1.0];
    g_fps_label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    g_fps_label.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    g_fps_label.layer.cornerRadius = 6;
    g_fps_label.layer.masksToBounds = YES;
    g_fps_label.textAlignment = NSTextAlignmentCenter;
    g_fps_label.text = @"60.0 FPS";
    [g_overlay_container addSubview:g_fps_label];
  });
}

void SetBoxingStyle(int style) {
  g_boxing_style = style;
}

void SetStraightCalibrationEnabled(bool enabled) {
  g_straight_calibration = enabled;
}

#ifdef __OBJC__
UIViewController* MakeLayoutEditor() {
  UIViewController* vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.08 alpha:1.0];

  UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(0, 40, vc.view.bounds.size.width, 40)];
  lbl.text = @"Fight Night Champion Touch Controls - Mode Switched";
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
  [done addAction:[UIAction actionWithHandler:^(UIAction*) {
    [vc dismissViewControllerAnimated:YES completion:nil];
  }] forControlEvents:UIControlEventTouchUpInside];
  [vc.view addSubview:done];

  return vc;
}
#endif

}  // namespace fnc::touch
