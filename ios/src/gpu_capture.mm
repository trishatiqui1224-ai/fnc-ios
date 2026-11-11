// In-app Metal capture for the Vulkan renderer on iOS.

#import <Metal/Metal.h>
#import <UIKit/UIKit.h>

#include <rex/logging.h>
#include <dlfcn.h>

#include "gpu_capture.h"
#include "launcher.h"

namespace {
constexpr int64_t kCaptureMs = 200;

using SetVulkanTraceEnabled = void (*)(bool);

SetVulkanTraceEnabled FindVulkanTraceControl() {
  NSString* path = [NSBundle.mainBundle.privateFrameworksPath
      stringByAppendingPathComponent:@"librexgpu-xenos.dylib"];
  void* handle = dlopen(path.fileSystemRepresentation, RTLD_LAZY | RTLD_NOLOAD);
  if (!handle) {
    return nullptr;
  }
  auto control = reinterpret_cast<SetVulkanTraceEnabled>(
      dlsym(handle, "FncSetVulkanTraceEnabled"));
  dlclose(handle);
  return control;
}
}

@interface FNCCaptureButton : UIButton
@end

@implementation FNCCaptureButton {
  BOOL _busy;
}

- (instancetype)init {
  if ((self = [super initWithFrame:CGRectZero])) {
    UIButtonConfiguration* c = UIButtonConfiguration.filledButtonConfiguration;
    c.baseBackgroundColor = [UIColor colorWithRed:0.75 green:0.1 blue:0.1 alpha:0.85];
    c.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    c.contentInsets = NSDirectionalEdgeInsetsMake(4, 10, 4, 10);
    self.configuration = c;
    [self setTitle:@"CAPTURE" forState:UIControlStateNormal];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:12];
    [self addTarget:self action:@selector(capture) forControlEvents:UIControlEventTouchUpInside];
  }
  return self;
}

- (void)setLabel:(NSString*)text {
  UIButtonConfiguration* c = self.configuration;
  c.title = text;
  self.configuration = c;
  [self layoutInSuperview];
}

- (void)layoutInSuperview {
  UIView* parent = self.superview;
  if (!parent) {
    return;
  }
  [self sizeToFit];
  const UIEdgeInsets safe = parent.safeAreaInsets;
  const CGSize s = self.bounds.size;
  self.frame = CGRectMake(parent.bounds.size.width - safe.right - s.width - 8, parent.bounds.size.height - safe.bottom - s.height - 8,
                          s.width, s.height);
}

- (void)capture {
  if (_busy) {
    return;
  }
  MTLCaptureManager* manager = MTLCaptureManager.sharedCaptureManager;
  if (![manager supportsDestination:MTLCaptureDestinationGPUTraceDocument]) {
    REXLOG_ERROR("[gpu-capture] Metal says it cannot write a capture document: capturing was "
                 "not enabled before the device was created");
    [self setLabel:@"NOT AVAILABLE"];
    return;
  }
  NSString* dir =
      @((fnc::launcher::Documents() / "captures").c_str());
  NSError* directoryError = nil;
  if (![NSFileManager.defaultManager createDirectoryAtPath:dir
                               withIntermediateDirectories:YES
                                                attributes:nil
                                                     error:&directoryError]) {
    REXLOG_ERROR("[gpu-capture] cannot create directory: {}", directoryError.localizedDescription.UTF8String);
    [self setLabel:@"FAILED"];
    return;
  }
  NSDateFormatter* f = [[NSDateFormatter alloc] init];
  f.dateFormat = @"yyyy-MM-dd_HH-mm-ss-SSS";
  NSString* path = [dir stringByAppendingPathComponent:
                            [[f stringFromDate:NSDate.date] stringByAppendingString:@".gputrace"]];

  MTLCaptureDescriptor* d = [[MTLCaptureDescriptor alloc] init];
  d.captureObject = MTLCreateSystemDefaultDevice();  // the one MoltenVK uses
  d.destination = MTLCaptureDestinationGPUTraceDocument;
  d.outputURL = [NSURL fileURLWithPath:path];
  NSError* error = nil;
  if (![manager startCaptureWithDescriptor:d error:&error]) {
    REXLOG_ERROR("[gpu-capture] could not start: {}", error.localizedDescription.UTF8String);
    [self setLabel:@"FAILED"];
    return;
  }
  _busy = YES;
  [self setLabel:@"CAPTURING…"];
  REXLOG_INFO("[gpu-capture] started -> {}", path.UTF8String);
  const auto trace_control = FindVulkanTraceControl();
  if (trace_control) {
    trace_control(true);
  } else {
    REXLOG_WARN("[gpu-capture] Vulkan trace control unavailable");
  }
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kCaptureMs * NSEC_PER_MSEC),
                 dispatch_get_main_queue(), ^{
                   if (trace_control) {
                     trace_control(false);
                   }
                   [manager stopCapture];
                   REXLOG_INFO("[gpu-capture] stopped after {} ms: {}", kCaptureMs,
                               path.lastPathComponent.UTF8String);
                   [self setLabel:[NSFileManager.defaultManager fileExistsAtPath:path] ? @"SAVED" : @"FAILED"];
                   dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                                  dispatch_get_main_queue(), ^{
                                    self->_busy = NO;
                                    [self setLabel:@"CAPTURE"];
                                  });
                 });
}

@end

namespace fnc::gpu_capture {

void InstallButton() {
  static bool installed = false;
  if (installed) {
    return;
  }
  UIWindow* window = nil;
  for (UIScene* scene in UIApplication.sharedApplication.connectedScenes) {
    if ([scene isKindOfClass:UIWindowScene.class] &&
        ((UIWindowScene*)scene).screen == UIScreen.mainScreen) {
      for (UIWindow* w in ((UIWindowScene*)scene).windows) {
        if (w.isKeyWindow || !window) {
          window = w;
        }
      }
    }
  }
  if (!window) {
    return;
  }
  FNCCaptureButton* button = [[FNCCaptureButton alloc] init];
  [window addSubview:button];
  button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
  [button layoutInSuperview];
  installed = true;
  REXLOG_INFO("[gpu-capture] button on screen (Metal capture to documents: {})",
              [MTLCaptureManager.sharedCaptureManager
                  supportsDestination:MTLCaptureDestinationGPUTraceDocument]
                  ? "available"
                  : "NOT available");
}

}  // namespace fnc::gpu_capture
