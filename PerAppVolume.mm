#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <math.h>

static NSString * const PVDefaultsKey = @"com.szq.perappvolume.settings";
static const void *PVOriginalVolumeKey = &PVOriginalVolumeKey;
static BOOL PVEnabled=YES, PVStereo=NO, PVFloatingEnabled=NO, PVOverVolume=NO, PVBackgroundAudio=NO, PVMuted=NO;
static float PVGain=1.0f, PVLeft=1.0f, PVRight=1.0f;
static NSHashTable<AVAudioPlayer *> *PVAudioPlayers;
static NSHashTable<AVPlayer *> *PVPlayers;
static UIWindow *PVWindow, *PVBallWindow;
static BOOL PVHooksInstalled=NO;

static float PVClamp(float v,float max){ if(!isfinite(v))return 1; return fminf(max,fmaxf(0,v)); }
static void PVLoad(void){
 NSDictionary*d=[[NSUserDefaults standardUserDefaults] dictionaryForKey:PVDefaultsKey]; if(![d isKindOfClass:NSDictionary.class])return;
 PVEnabled=d[@"enabled"]?[d[@"enabled"] boolValue]:YES; PVGain=PVClamp([d[@"gain"] floatValue],2);
 PVStereo=[d[@"stereo"] boolValue]; PVLeft=PVClamp(d[@"left"]?[d[@"left"] floatValue]:1,2); PVRight=PVClamp(d[@"right"]?[d[@"right"] floatValue]:1,2);
 PVFloatingEnabled=[d[@"floating"] boolValue]; PVOverVolume=[d[@"over"] boolValue]; PVBackgroundAudio=[d[@"background"] boolValue]; PVMuted=[d[@"muted"] boolValue];
}
static void PVSave(void){ [[NSUserDefaults standardUserDefaults] setObject:@{@"enabled":@(PVEnabled),@"gain":@(PVGain),@"stereo":@(PVStereo),@"left":@(PVLeft),@"right":@(PVRight),@"floating":@(PVFloatingEnabled),@"over":@(PVOverVolume),@"background":@(PVBackgroundAudio),@"muted":@(PVMuted)} forKey:PVDefaultsKey]; }
static float PVApplied(float v){ if(PVMuted)return 0; float gain=PVEnabled?PVGain:1; return PVClamp(v*gain,PVOverVolume?2:1); }
@interface AVAudioPlayer(PVHook)
-(void)pv_original_setVolume:(float)v;
@end
@implementation AVAudioPlayer(PVHook)
-(void)pv_original_setVolume:(float)v{ objc_setAssociatedObject(self,PVOriginalVolumeKey,@(PVClamp(v,1)),OBJC_ASSOCIATION_RETAIN_NONATOMIC); [self pv_original_setVolume:PVApplied(v)]; [PVAudioPlayers addObject:self];}
@end
@interface AVPlayer(PVHook)
-(void)pv_original_setVolume:(float)v;
@end
@implementation AVPlayer(PVHook)
-(void)pv_original_setVolume:(float)v{ objc_setAssociatedObject(self,PVOriginalVolumeKey,@(PVClamp(v,1)),OBJC_ASSOCIATION_RETAIN_NONATOMIC); [self pv_original_setVolume:PVApplied(v)]; [PVPlayers addObject:self];}
@end
static void PVSwizzle(Class c,SEL a,SEL b){Method x=class_getInstanceMethod(c,a),y=class_getInstanceMethod(c,b);if(x&&y)method_exchangeImplementations(x,y);}
static void PVRefresh(void){
 for(AVAudioPlayer*p in PVAudioPlayers.allObjects){NSNumber*n=objc_getAssociatedObject(p,PVOriginalVolumeKey);if(n)[p pv_original_setVolume:PVApplied(n.floatValue)];}
 for(AVPlayer*p in PVPlayers.allObjects){NSNumber*n=objc_getAssociatedObject(p,PVOriginalVolumeKey);if(n)[p pv_original_setVolume:PVApplied(n.floatValue)];}
}
static void PVInstall(void){if(PVHooksInstalled)return;PVHooksInstalled=YES;PVAudioPlayers=[NSHashTable weakObjectsHashTable];PVPlayers=[NSHashTable weakObjectsHashTable];PVSwizzle(AVAudioPlayer.class,@selector(setVolume:),@selector(pv_original_setVolume:));PVSwizzle(AVPlayer.class,@selector(setVolume:),@selector(pv_original_setVolume:));}

static UIWindowScene *PVScene(void){for(UIScene*s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class]&&s.activationState==UISceneActivationStateForegroundActive)return (id)s;return nil;}
static void PVShowPanel(void);
@interface PVGradientView:UIView
@end
@implementation PVGradientView
+(Class)layerClass{return CAGradientLayer.class;}
-(void)didMoveToWindow{[super didMoveToWindow];CAGradientLayer*l=(id)self.layer;l.colors=@[(id)[UIColor colorWithRed:.025 green:.10 blue:.36 alpha:1].CGColor,(id)[UIColor colorWithRed:.20 green:.10 blue:.58 alpha:1].CGColor,(id)[UIColor colorWithRed:.04 green:.28 blue:.62 alpha:1].CGColor];l.startPoint=CGPointMake(0,0);l.endPoint=CGPointMake(1,1);l.locations=@[@0,@.5,@1];CABasicAnimation*a=[CABasicAnimation animationWithKeyPath:@"locations"];a.fromValue=@[@0,@.3,@.7];a.toValue=@[@.3,@.7,@1];a.duration=5;a.autoreverses=YES;a.repeatCount=HUGE_VALF;[l addAnimation:a forKey:@"pv.flow"];}
@end
static UILabel *PVLabel(NSString*s,CGFloat size,UIFontWeight weight,UIColor*c){UILabel*l=[UILabel new];l.text=s;l.font=[UIFont systemFontOfSize:size weight:weight];l.textColor=c;return l;}
static UIButton *PVButton(NSString*s){UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];[b setTitle:s forState:UIControlStateNormal];[b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];return b;}
@interface PVPanel:UIViewController
@property(nonatomic,strong)UISlider*mainSlider;@property(nonatomic,strong)UISlider*leftSlider;@property(nonatomic,strong)UISlider*rightSlider;@property(nonatomic,strong)UILabel*mainValue;@property(nonatomic,strong)UIStackView*content;@property(nonatomic,strong)UIView*stereoRow;
@end
@implementation PVPanel
-(void)viewDidLoad{[super viewDidLoad];PVGradientView*bg=[PVGradientView new];bg.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:bg];[NSLayoutConstraint activateConstraints:@[[bg.topAnchor constraintEqualToAnchor:self.view.topAnchor],[bg.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[bg.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[bg.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
 self.view.layer.cornerRadius=24;self.view.clipsToBounds=YES;
 UILabel*title=PVLabel(@"我的音量我做主",22,UIFontWeightBold,UIColor.whiteColor);title.translatesAutoresizingMaskIntoConstraints=NO;
 CAGradientLayer*textGradient=[CAGradientLayer layer];textGradient.frame=CGRectMake(0,0,230,34);textGradient.colors=@[(id)UIColor.cyanColor.CGColor,(id)UIColor.systemPinkColor.CGColor,(id)UIColor.yellowColor.CGColor];textGradient.startPoint=CGPointZero;textGradient.endPoint=CGPointMake(1,0);[textGradient addAnimation:({CABasicAnimation*a=[CABasicAnimation animationWithKeyPath:@"locations"];a.fromValue=@[@0,@.4,@.8];a.toValue=@[@.2,@.7,@1];a.duration=3;a.repeatCount=HUGE_VALF;a.autoreverses=YES;a;}) forKey:@"pv.title.flow"];title.layer.mask=(id)textGradient;
 UIButton*settings=PVButton(@"⚙");settings.titleLabel.font=[UIFont systemFontOfSize:25];[settings addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];settings.translatesAutoresizingMaskIntoConstraints=NO;
 self.mainValue=PVLabel(@"100%",28,UIFontWeightBold,UIColor.whiteColor);self.mainValue.textAlignment=NSTextAlignmentCenter;
 self.mainSlider=[UISlider new];self.mainSlider.minimumValue=0;self.mainSlider.maximumValue=PVOverVolume?2:1;self.mainSlider.value=PVGain;[self.mainSlider addTarget:self action:@selector(mainChanged:) forControlEvents:UIControlEventValueChanged];
 UIButton*mute=PVButton(PVMuted?@"取消静音":@"静音");[mute addTarget:self action:@selector(toggleMute:) forControlEvents:UIControlEventTouchUpInside];
 UIStackView*buttons=[[UIStackView alloc]initWithArrangedSubviews:@[mute]];buttons.axis=UILayoutConstraintAxisHorizontal;buttons.alignment=UIStackViewAlignmentCenter;buttons.distribution=UIStackViewDistributionEqualSpacing;
 self.stereoRow=[UIView new];self.stereoRow.translatesAutoresizingMaskIntoConstraints=NO;
 self.leftSlider=[UISlider new];self.rightSlider=[UISlider new];for(UISlider*s in @[self.leftSlider,self.rightSlider]){s.minimumValue=0;s.maximumValue=PVOverVolume?2:1;}
 self.leftSlider.value=PVLeft;self.rightSlider.value=PVRight;[self.leftSlider addTarget:self action:@selector(channelChanged:) forControlEvents:UIControlEventValueChanged];[self.rightSlider addTarget:self action:@selector(channelChanged:) forControlEvents:UIControlEventValueChanged];
 UIStackView*lr=[[UIStackView alloc]initWithArrangedSubviews:@[PVLabel(@"左声道",13,UIFontWeightMedium,UIColor.whiteColor),self.leftSlider,PVLabel(@"右声道",13,UIFontWeightMedium,UIColor.whiteColor),self.rightSlider]];lr.axis=UILayoutConstraintAxisVertical;lr.spacing=5;lr.translatesAutoresizingMaskIntoConstraints=NO;[self.stereoRow addSubview:lr];[NSLayoutConstraint activateConstraints:@[[lr.topAnchor constraintEqualToAnchor:self.stereoRow.topAnchor],[lr.bottomAnchor constraintEqualToAnchor:self.stereoRow.bottomAnchor],[lr.leadingAnchor constraintEqualToAnchor:self.stereoRow.leadingAnchor],[lr.trailingAnchor constraintEqualToAnchor:self.stereoRow.trailingAnchor]]];self.stereoRow.hidden=!PVStereo;
 UILabel*footer=PVLabel(@"By 是你的梓柒呀",11,UIFontWeightRegular,[UIColor.whiteColor colorWithAlphaComponent:.8]);UIButton*link=PVButton(@"github.com/szq-4070/PerAppVolume");link.titleLabel.font=[UIFont systemFontOfSize:10];[link addTarget:self action:@selector(openGitHub) forControlEvents:UIControlEventTouchUpInside];
 UIStackView*foot=[[UIStackView alloc]initWithArrangedSubviews:@[footer,link]];foot.axis=UILayoutConstraintAxisVertical;foot.alignment=UIStackViewAlignmentCenter;foot.spacing=2;
 self.content=[[UIStackView alloc]initWithArrangedSubviews:@[title,self.mainValue,self.mainSlider,buttons,self.stereoRow,foot]];self.content.axis=UILayoutConstraintAxisVertical;self.content.spacing=13;self.content.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.content];[self.view addSubview:settings];
 [NSLayoutConstraint activateConstraints:@[[self.content.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],[self.content.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],[self.content.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:15],[self.content.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.bottomAnchor constant:-10],[settings.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:8],[settings.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-10],[settings.widthAnchor constraintEqualToConstant:40],[settings.heightAnchor constraintEqualToConstant:40],[self.view.widthAnchor constraintEqualToConstant:340]]];
}
-(void)mainChanged:(UISlider*)s{PVGain=s.value;self.mainValue.text=[NSString stringWithFormat:@"%.0f%%",PVGain*100];PVSave();PVRefresh();}
-(void)channelChanged:(UISlider*)s{PVLeft=self.leftSlider.value;PVRight=self.rightSlider.value;PVSave();}
-(void)toggleMute:(UIButton*)b{PVMuted=!PVMuted;[b setTitle:PVMuted?@"取消静音":@"静音" forState:UIControlStateNormal];PVSave();PVRefresh();}
-(void)openGitHub{NSURL*u=[NSURL URLWithString:@"https://github.com/szq-4070/PerAppVolume"];if(u)[UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];}
-(void)showSettings{UIAlertController*a=[UIAlertController alertControllerWithTitle:@"设置" message:@"音频属性与控制选项" preferredStyle:UIAlertControllerStyleActionSheet];
 NSArray*items=@[[NSString stringWithFormat:@"超音量：%@",PVOverVolume?@"开":@"关"],[NSString stringWithFormat:@"双声道：%@",PVStereo?@"开":@"关"],[NSString stringWithFormat:@"悬浮球：%@",PVFloatingEnabled?@"开":@"关"],[NSString stringWithFormat:@"后台不冲突播放：%@",PVBackgroundAudio?@"开":@"关"],[NSString stringWithFormat:@"音量控制：%@",PVEnabled?@"开":@"关"]];
 for(NSUInteger i=0;i<items.count;i++){[a addAction:[UIAlertAction actionWithTitle:items[i] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction*x){switch(i){case 0:PVOverVolume=!PVOverVolume;break;case 1:PVStereo=!PVStereo;self.stereoRow.hidden=!PVStereo;break;case 2:PVFloatingEnabled=!PVFloatingEnabled;break;case 3:PVBackgroundAudio=!PVBackgroundAudio;break;case 4:PVEnabled=!PVEnabled;break;}PVSave();PVRefresh();}]];}
 [a addAction:[UIAlertAction actionWithTitle:@"完成" style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.view;a.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width-30,20,1,1);[self presentViewController:a animated:YES completion:nil];}
@end
@interface PVBall:UIView
@end
@implementation PVBall
-(instancetype)init{if((self=[super initWithFrame:CGRectMake(0,0,54,54)])){self.backgroundColor=[UIColor colorWithRed:.24 green:.25 blue:.85 alpha:.9];self.layer.cornerRadius=27;self.layer.borderWidth=1;self.layer.borderColor=UIColor.whiteColor.CGColor;UILabel*l=PVLabel(@"音",22,UIFontWeightBold,UIColor.whiteColor);l.frame=self.bounds;l.textAlignment=NSTextAlignmentCenter;[self addSubview:l];UITapGestureRecognizer*t=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(open)];[self addGestureRecognizer:t];}return self;}
-(void)open{PVShowPanel();}
@end
static void PVUpdateBall(void){if(!PVFloatingEnabled){PVBallWindow.hidden=YES;return;}UIWindowScene*s=PVScene();if(!s)return;if(!PVBallWindow){PVBallWindow=[[UIWindow alloc]initWithWindowScene:s];PVBallWindow.windowLevel=UIWindowLevelAlert+1;PVBallWindow.backgroundColor=UIColor.clearColor;PVBallWindow.rootViewController=[UIViewController new];PVBallWindow.rootViewController.view.backgroundColor=UIColor.clearColor;[PVBallWindow.rootViewController.view addSubview:[PVBall new]];}PVBallWindow.frame=CGRectMake(0,0,54,54);PVBallWindow.center=CGPointMake(s.coordinateSpace.bounds.size.width-45,s.coordinateSpace.bounds.size.height/2);PVBallWindow.hidden=NO;}
static void PVShowPanel(void){if(!NSThread.isMainThread){dispatch_async(dispatch_get_main_queue(),^{PVShowPanel();});return;}UIWindowScene*s=PVScene();if(!s)return;if(!PVWindow||PVWindow.windowScene!=s){PVWindow=[[UIWindow alloc]initWithWindowScene:s];PVWindow.windowLevel=UIWindowLevelAlert;PVWindow.backgroundColor=UIColor.clearColor;PVWindow.rootViewController=[PVPanel new];}PVWindow.frame=CGRectMake(0,0,340,300);PVWindow.center=CGPointMake(s.coordinateSpace.bounds.size.width/2,s.coordinateSpace.bounds.size.height/2);PVWindow.hidden=NO;[PVWindow makeKeyAndVisible];PVUpdateBall();}
@interface PVLongPressInstaller:NSObject
@end
@implementation PVLongPressInstaller
+(void)install{dispatch_async(dispatch_get_main_queue(),^{for(UIWindowScene*s in UIApplication.sharedApplication.connectedScenes)if([s isKindOfClass:UIWindowScene.class])for(UIWindow*w in s.windows){if(w==PVWindow||w==PVBallWindow)continue;UIView*v=w.rootViewController.view;if(!v||objc_getAssociatedObject(v,@selector(install)))continue;UILongPressGestureRecognizer*g=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPress:)];g.numberOfTouchesRequired=2;g.minimumPressDuration=.7;[v addGestureRecognizer:g];objc_setAssociatedObject(v,@selector(install),@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}});}
+(void)longPress:(UILongPressGestureRecognizer*)g{if(g.state==UIGestureRecognizerStateBegan)PVShowPanel();}
@end
static void PVShowStartup(void){PVShowPanel();PVUpdateBall();}
__attribute__((constructor))static void PerAppVolumeInitialize(void){@autoreleasepool{PVLoad();PVInstall();dispatch_async(dispatch_get_main_queue(),^{dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1*NSEC_PER_SEC)),dispatch_get_main_queue(),^{PVShowStartup();[PVLongPressInstaller install];});});}}
