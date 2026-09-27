#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

#pragma mark - Persistent settings

static NSString * const PVDefaultsKey = @"com.szq.perappvolume.settings";
static NSString * const PVEnabledKey = @"enabled";
static NSString * const PVMasterKey = @"master";
static NSString * const PVLeftKey = @"left";
static NSString * const PVRightKey = @"right";
static NSString * const PVBalanceKey = @"stereo";

static BOOL PVEnabled = YES;
static float PVMaster = 1.0f;
static float PVLeft = 1.0f;
static float PVRight = 1.0f;
static BOOL PVStereo = NO;

static float PVClamp(float value) {
    if (!isfinite(value)) return 1.0f;
    return fminf(2.0f, fmaxf(0.0f, value));
}

static void PVLoadSettings(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PVDefaultsKey];
    if (![d isKindOfClass:NSDictionary.class]) return;
    PVEnabled = d[PVEnabledKey] ? [d[PVEnabledKey] boolValue] : YES;
    PVMaster = PVClamp(d[PVMasterKey] ? [d[PVMasterKey] floatValue] : 1.0f);
    PVLeft = PVClamp(d[PVLeftKey] ? [d[PVLeftKey] floatValue] : 1.0f);
    PVRight = PVClamp(d[PVRightKey] ? [d[PVRightKey] floatValue] : 1.0f);
    PVStereo = d[PVBalanceKey] ? [d[PVBalanceKey] boolValue] : NO;
}

static void PVSaveSettings(void) {
    NSDictionary *d = @{
        PVEnabledKey: @(PVEnabled),
        PVMasterKey: @(PVMaster),
        PVLeftKey: @(PVLeft),
        PVRightKey: @(PVRight),
        PVBalanceKey: @(PVStereo)
    };
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:PVDefaultsKey];
}

static float PVGainForChannel(BOOL right) {
    if (!PVEnabled) return 1.0f;
    if (!PVStereo) return PVMaster;
    return PVClamp((right ? PVRight : PVLeft) * PVMaster);
}

#pragma mark - Runtime hooks
/*
 The hooks affect volume values supplied through AVAudioPlayer and AVPlayer.
 They do not intercept every CoreAudio, AudioQueue, WebRTC, game-engine, or
 system-managed audio path. A successful hook is not proof that a given app's
 audible output is controlled.
 */

static void PVSwizzleInstanceMethod(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) return;

    BOOL added = class_addMethod(cls, original, method_getImplementation(b),
                                 method_getTypeEncoding(b));
    if (added) {
        class_replaceMethod(cls, replacement, method_getImplementation(a),
                            method_getTypeEncoding(a));
    } else {
        method_exchangeImplementations(a, b);
    }
}

@interface AVAudioPlayer (PVVolumeHook)
- (void)pv_setVolume:(float)volume;
@end

@implementation AVAudioPlayer (PVVolumeHook)
- (void)pv_setVolume:(float)volume {
    float gain = PVGainForChannel(NO);
    [self pv_setVolume:fminf(1.0f, fmaxf(0.0f, volume * gain))];
}
@end

@interface AVPlayer (PVVolumeHook)
- (void)pv_setVolume:(float)volume;
@end

@implementation AVPlayer (PVVolumeHook)
- (void)pv_setVolume:(float)volume {
    float gain = PVGainForChannel(NO);
    [self pv_setVolume:fminf(1.0f, fmaxf(0.0f, volume * gain))];
}
@end

static BOOL PVHooksInstalled = NO;
static void PVInstallHooks(void) {
    if (PVHooksInstalled) return;
    PVHooksInstalled = YES;
    PVSwizzleInstanceMethod(AVAudioPlayer.class, @selector(setVolume:), @selector(pv_setVolume:));
    PVSwizzleInstanceMethod(AVPlayer.class, @selector(setVolume:), @selector(pv_setVolume:));
}

#pragma mark - Control panel

@interface PVPanelController : UIViewController
@property(nonatomic, strong) UILabel *masterLabel;
@property(nonatomic, strong) UILabel *leftLabel;
@property(nonatomic, strong) UILabel *rightLabel;
@property(nonatomic, strong) UISlider *masterSlider;
@property(nonatomic, strong) UISlider *leftSlider;
@property(nonatomic, strong) UISlider *rightSlider;
@property(nonatomic, strong) UISwitch *enabledSwitch;
@property(nonatomic, strong) UISwitch *stereoSwitch;
@end

@implementation PVPanelController

- (UILabel *)label:(NSString *)text size:(CGFloat)size {
    UILabel *v = [[UILabel alloc] init];
    v.text = text;
    v.font = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
    v.textColor = UIColor.labelColor;
    v.translatesAutoresizingMaskIntoConstraints = NO;
    return v;
}

- (UISlider *)sliderWithValue:(float)value action:(SEL)action {
    UISlider *s = [[UISlider alloc] init];
    s.minimumValue = 0.0f;
    s.maximumValue = 2.0f;
    s.value = value;
    s.translatesAutoresizingMaskIntoConstraints = NO;
    [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    return s;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.97];
    self.view.layer.cornerRadius = 20.0;
    self.view.layer.borderWidth = 1.0;
    self.view.layer.borderColor = UIColor.separatorColor.CGColor;
    self.view.clipsToBounds = YES;

    UILabel *title = [self label:@"PerAppVolume" size:21];
    UILabel *status = [self label:@"AVAudioPlayer / AVPlayer Hook（有限覆盖）" size:11];
    status.textColor = UIColor.secondaryLabelColor;

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"关闭" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];

    self.masterLabel = [self label:@"" size:15];
    self.leftLabel = [self label:@"" size:13];
    self.rightLabel = [self label:@"" size:13];
    self.masterSlider = [self sliderWithValue:PVMaster action:@selector(masterChanged:)];
    self.leftSlider = [self sliderWithValue:PVLeft action:@selector(leftChanged:)];
    self.rightSlider = [self sliderWithValue:PVRight action:@selector(rightChanged:)];

    UILabel *enabledText = [self label:@"启用音量 Hook" size:14];
    self.enabledSwitch = [[UISwitch alloc] init];
    self.enabledSwitch.on = PVEnabled;
    self.enabledSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.enabledSwitch addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *stereoText = [self label:@"独立左右声道" size:14];
    self.stereoSwitch = [[UISwitch alloc] init];
    self.stereoSwitch.on = PVStereo;
    self.stereoSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stereoSwitch addTarget:self action:@selector(stereoChanged:) forControlEvents:UIControlEventValueChanged];

    UIStackView *header = [[UIStackView alloc] initWithArrangedSubviews:@[title, close]];
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    header.distribution = UIStackViewDistributionEqualSpacing;

    UIStackView *enabledRow = [[UIStackView alloc] initWithArrangedSubviews:@[enabledText, self.enabledSwitch]];
    enabledRow.axis = UILayoutConstraintAxisHorizontal;
    enabledRow.alignment = UIStackViewAlignmentCenter;
    enabledRow.distribution = UIStackViewDistributionEqualSpacing;

    UIStackView *stereoRow = [[UIStackView alloc] initWithArrangedSubviews:@[stereoText, self.stereoSwitch]];
    stereoRow.axis = UILayoutConstraintAxisHorizontal;
    stereoRow.alignment = UIStackViewAlignmentCenter;
    stereoRow.distribution = UIStackViewDistributionEqualSpacing;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        header, status, self.masterLabel, self.masterSlider,
        self.leftLabel, self.leftSlider, self.rightLabel, self.rightSlider,
        enabledRow, stereoRow
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16],
        [self.view.widthAnchor constraintEqualToConstant:340]
    ]];
    [self updateLabels];
}

- (void)updateLabels {
    self.masterLabel.text = [NSString stringWithFormat:@"主音量  %.0f%%", PVMaster * 100.0f];
    self.leftLabel.text = [NSString stringWithFormat:@"左声道  %.0f%%", PVLeft * 100.0f];
    self.rightLabel.text = [NSString stringWithFormat:@"右声道  %.0f%%", PVRight * 100.0f];
    self.leftSlider.enabled = PVStereo;
    self.rightSlider.enabled = PVStereo;
}

- (void)masterChanged:(UISlider *)s {
    PVMaster = PVClamp(s.value);
    PVSaveSettings();
    [self updateLabels];
}
- (void)leftChanged:(UISlider *)s {
    PVLeft = PVClamp(s.value);
    PVSaveSettings();
    [self updateLabels];
}
- (void)rightChanged:(UISlider *)s {
    PVRight = PVClamp(s.value);
    PVSaveSettings();
    [self updateLabels];
}
- (void)enabledChanged:(UISwitch *)s {
    PVEnabled = s.on;
    PVSaveSettings();
}
- (void)stereoChanged:(UISwitch *)s {
    PVStereo = s.on;
    PVSaveSettings();
    [self updateLabels];
}
- (void)closePanel {
    self.view.window.hidden = YES;
}

@end

static UIWindow *PVWindow = nil;
static UIButton *PVOpenButton = nil;

static UIWindowScene *PVActiveScene(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class] &&
            scene.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static void PVShowPanel(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ PVShowPanel(); });
        return;
    }
    UIWindowScene *scene = PVActiveScene();
    if (!scene) return;

    if (!PVWindow) {
        PVWindow = [[UIWindow alloc] initWithWindowScene:scene];
        PVWindow.windowLevel = UIWindowLevelAlert + 1;
        PVWindow.backgroundColor = UIColor.clearColor;
        PVWindow.rootViewController = [[PVPanelController alloc] init];
        PVWindow.frame = CGRectMake(0, 0, 340, 360);
    }
    PVWindow.hidden = NO;
    PVWindow.alpha = 1.0;
    PVWindow.rootViewController.view.hidden = NO;
    PVWindow.center = CGPointMake(scene.coordinateSpace.bounds.size.width / 2.0,
                                  scene.coordinateSpace.bounds.size.height / 2.0);
    [PVWindow makeKeyAndVisible];
}

static void PVShowStartupAlert(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ PVShowStartupAlert(); });
        return;
    }
    UIWindowScene *scene = PVActiveScene();
    if (!scene) return;
    UIViewController *presenter = scene.windows.firstObject.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter || !presenter.view.window) return;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"PerAppVolume 已初始化"
        message:@"动态库初始化成功。\n已安装 AVAudioPlayer / AVPlayer 音量 Hook。\n注意：这不代表所有音频路径均可控制；当前增益上限受系统播放器音量范围限制。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"打开控制面板"
        style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            PVShowPanel();
        }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
        style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

__attribute__((constructor))
static void PerAppVolumeInitialize(void) {
    @autoreleasepool {
        PVLoadSettings();
        PVInstallHooks();
        NSLog(@"[PerAppVolume] initialized; AVAudioPlayer and AVPlayer hooks installed");
        dispatch_async(dispatch_get_main_queue(), ^{
            // Delay until the host app has a foreground window.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                PVShowStartupAlert();
            });
        });
    }
}
