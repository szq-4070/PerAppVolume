#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <math.h>

static NSString * const PVDefaultsKey = @"com.szq.perappvolume.settings";
static NSString * const PVEnabledKey = @"enabled";
static NSString * const PVGainKey = @"gain";
static const void *PVOriginalVolumeKey = &PVOriginalVolumeKey;
static BOOL PVEnabled = YES;
static float PVGain = 1.0f;
static BOOL PVHooksInstalled = NO;
static NSHashTable<AVAudioPlayer *> *PVAudioPlayers;
static NSHashTable<AVPlayer *> *PVPlayers;

static float PVClamp(float v) {
    if (!isfinite(v)) return 1.0f;
    return fminf(1.0f, fmaxf(0.0f, v));
}
static void PVLoad(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey:PVDefaultsKey];
    if (![d isKindOfClass:NSDictionary.class]) return;
    PVEnabled = d[PVEnabledKey] ? [d[PVEnabledKey] boolValue] : YES;
    PVGain = PVClamp(d[PVGainKey] ? [d[PVGainKey] floatValue] : 1.0f);
}
static void PVSave(void) {
    [[NSUserDefaults standardUserDefaults] setObject:@{PVEnabledKey:@(PVEnabled), PVGainKey:@(PVGain)} forKey:PVDefaultsKey];
}
static float PVApplied(float original) { return PVEnabled ? PVClamp(original * PVGain) : PVClamp(original); }

@interface AVAudioPlayer (PVHook)
- (void)pv_original_setVolume:(float)value;
@end
@implementation AVAudioPlayer (PVHook)
- (void)pv_original_setVolume:(float)value {
    objc_setAssociatedObject(self, PVOriginalVolumeKey, @(PVClamp(value)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self pv_original_setVolume:PVApplied(value)];
    [PVAudioPlayers addObject:self];
}
@end

@interface AVPlayer (PVHook)
- (void)pv_original_setVolume:(float)value;
@end
@implementation AVPlayer (PVHook)
- (void)pv_original_setVolume:(float)value {
    objc_setAssociatedObject(self, PVOriginalVolumeKey, @(PVClamp(value)), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self pv_original_setVolume:PVApplied(value)];
    [PVPlayers addObject:self];
}
@end

static void PVSwizzle(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original), b = class_getInstanceMethod(cls, replacement);
    if (!a || !b) return;
    method_exchangeImplementations(a, b);
}
static void PVRefreshPlayers(void) {
    for (AVAudioPlayer *p in PVAudioPlayers.allObjects) {
        NSNumber *n = objc_getAssociatedObject(p, PVOriginalVolumeKey);
        if (n) [p pv_original_setVolume:PVApplied(n.floatValue)];
    }
    for (AVPlayer *p in PVPlayers.allObjects) {
        NSNumber *n = objc_getAssociatedObject(p, PVOriginalVolumeKey);
        if (n) [p pv_original_setVolume:PVApplied(n.floatValue)];
    }
}
static void PVInstall(void) {
    if (PVHooksInstalled) return;
    PVHooksInstalled = YES;
    PVAudioPlayers = [NSHashTable weakObjectsHashTable];
    PVPlayers = [NSHashTable weakObjectsHashTable];
    PVSwizzle(AVAudioPlayer.class, @selector(setVolume:), @selector(pv_original_setVolume:));
    PVSwizzle(AVPlayer.class, @selector(setVolume:), @selector(pv_original_setVolume:));
}

@interface PVPanel : UIViewController
@property(nonatomic,strong) UISlider *slider;
@property(nonatomic,strong) UILabel *valueLabel;
@property(nonatomic,strong) UISwitch *enabledSwitch;
@end
@implementation PVPanel
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor.secondarySystemBackgroundColor colorWithAlphaComponent:0.98];
    self.view.layer.cornerRadius = 18;
    self.view.clipsToBounds = YES;
    UILabel *title = [[UILabel alloc] init]; title.text = @"PerAppVolume"; title.font = [UIFont boldSystemFontOfSize:21];
    self.valueLabel = [[UILabel alloc] init]; self.valueLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.slider = [[UISlider alloc] init]; self.slider.minimumValue = 0; self.slider.maximumValue = 1; self.slider.value = PVGain;
    [self.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    UILabel *switchTitle = [[UILabel alloc] init]; switchTitle.text = @"启用音量控制";
    self.enabledSwitch = [[UISwitch alloc] init]; self.enabledSwitch.on = PVEnabled;
    [self.enabledSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem]; [close setTitle:@"关闭面板" forState:UIControlStateNormal];
    [close addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[switchTitle,self.enabledSwitch]]; row.axis=UILayoutConstraintAxisHorizontal; row.distribution=UIStackViewDistributionEqualSpacing;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[title,self.valueLabel,self.slider,row,close]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=18; stack.translatesAutoresizingMaskIntoConstraints=NO;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],[stack.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:20],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-20],[self.view.widthAnchor constraintEqualToConstant:320]]];
    [self updateValue];
}
- (void)updateValue { self.valueLabel.text=[NSString stringWithFormat:@"音量倍率：%.0f%%（最高 100%%）",PVGain*100.0f]; }
- (void)sliderChanged:(UISlider *)s { PVGain=PVClamp(s.value); PVSave(); [self updateValue]; PVRefreshPlayers(); }
- (void)switchChanged:(UISwitch *)s { PVEnabled=s.on; PVSave(); PVRefreshPlayers(); }
- (void)closePanel { self.view.window.hidden=YES; }
@end

static UIWindow *PVWindow;
static UIWindowScene *PVScene(void) {
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class] && s.activationState==UISceneActivationStateForegroundActive) return (UIWindowScene *)s;
    return nil;
}
static void PVShowPanel(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ PVShowPanel(); }); return; }
    UIWindowScene *scene=PVScene(); if (!scene) return;
    if (!PVWindow) { PVWindow=[[UIWindow alloc] initWithWindowScene:scene]; PVWindow.windowLevel=UIWindowLevelAlert; PVWindow.backgroundColor=UIColor.clearColor; PVWindow.rootViewController=[PVPanel new]; }
    PVWindow.frame=CGRectMake(0,0,320,260); PVWindow.center=CGPointMake(CGRectGetMidX(scene.coordinateSpace.bounds),CGRectGetMidY(scene.coordinateSpace.bounds)); PVWindow.hidden=NO; [PVWindow makeKeyAndVisible];
}
static void PVShowAlert(void) {
    UIWindowScene *scene=PVScene(); if (!scene) return;
    UIWindow *w=nil; for (UIWindow *candidate in scene.windows) if (candidate.rootViewController && !candidate.hidden) { w=candidate; break; }
    UIViewController *vc=w.rootViewController; while (vc.presentedViewController) vc=vc.presentedViewController;
    if (!vc || !vc.view.window) return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"PerAppVolume 已加载" message:@"当前支持 AVAudioPlayer / AVPlayer 的音量属性。仅支持 0–100%，不支持所有音频引擎或左右声道独立处理。" preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"打开控制面板" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){ PVShowPanel(); }]];
    [a addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
__attribute__((constructor)) static void PerAppVolumeInitialize(void) {
    @autoreleasepool { PVLoad(); PVInstall(); NSLog(@"[PerAppVolume] AVFoundation volume hooks installed"); dispatch_async(dispatch_get_main_queue(), ^{ dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ PVShowAlert(); }); }); }
}
