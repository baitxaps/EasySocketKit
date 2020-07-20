//
//  TTVAudioManager.m
//  TouchTV
//
//  Created by 周启睿 on 2020/2/7.
//  Copyright © 2020 TouchTV. All rights reserved.
//

#import "TTVAudioManager.h"
#import "TTVAudioPlayer.h"
#import <CoreTelephony/CTCallCenter.h>
#import <CoreTelephony/CTCall.h>
#import <AVFoundation/AVFoundation.h>
#import "TTVSingleVideoModel.h"
#import "NSString+Category.h"
#import "TTVThisNews.h"

#define kTTVDataCacheSongListRecordType @"kTTVDataCacheSongListRecordType"
#define kTTVDataCacheSongListSeekTime   @"kTTVDataCacheSongListSeekTime"

@interface TTVAudioManager ()

@property (nonatomic,  copy) NSString* playUrl;
@property (nonatomic, strong) id audioNews;
@property (nonatomic, strong) RACDisposable *handler,*displosable;
@property (nonatomic, assign) BOOL notTheSameAudio;
@property (nonatomic, assign) BOOL  playing;
@property (nonatomic, strong) AudioCache  *audioCache;
@property (nonatomic, assign) double timeLength;
@property (nonatomic, strong) CTCallCenter *callCenter;

@property (nonatomic, strong) AudioListModel *currentSong;
@property (nonatomic, assign) NSInteger currentSongIndex;

//- (void)updateInfo:(id)model;
//- (TTVVAudioStatus)audioStatus;
@end


@implementation TTVAudioManager
singleton_implementation(TTVAudioManager);

// 无用
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (instancetype)init{
    self = [super init];
    if (self) {
        [self setup];
        
    }
    return self;
}

- (void)setup {
    [self bindingEvent];
    
    [self setupCallCenter];
    [self addNotification];
}

- (void)addNotification {
    //耳机插入和拔掉通知
    [[NSNotificationCenter defaultCenter] addObserver:self
          selector:@selector(audioRouteChangeListenerCallback:)
    name:AVAudioSessionRouteChangeNotification
     object:[AVAudioSession sharedInstance]];
    
//    [[NSNotificationCenter defaultCenter] addObserver:self
//      selector:@selector(audioInterruption:)
//       name:AVAudioSessionInterruptionNotification
//     object:[AVAudioSession sharedInstance]];
}

- (void)bindingEvent{
    @weakify(self);
    
    self.managerView.onSeekToBlock = ^(double value) {
        @strongify(self);
        double cur = self.totalTime * value;
        [self seekTo:cur];
      
        [self canAddAudioCompent];
    };
    
    self.managerView.onNextClickBlock = ^(id  _Nonnull obj) {
        @strongify(self);
        [self playNext];
        [self canAddAudioCompent];
    };
    
    self.managerView.onPlayClickBlock = ^(id  _Nonnull obj) {
        @strongify(self);
        [self changeAction];
        [self canAddAudioCompent];
    };
    
    self.managerView.onPrevClickBlock = ^(id  _Nonnull obj) {
        @strongify(self);
        [self playPrev];
        [self canAddAudioCompent];
    };
}

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
           // NSLog(@"耳机插入");
            break;
         
        //旧音频设备断开
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
            AVAudioSessionRouteDescription *previousRoute =interuptionDict[AVAudioSessionRouteChangePreviousRouteKey];
            AVAudioSessionPortDescription *previousOutput =previousRoute.outputs[0];
            NSString *portType =previousOutput.portType;
            
            if ([portType isEqualToString:AVAudioSessionPortHeadphones]) {
                // 拔掉耳机继续播放
                if (self.playing) {
                    [self resume];
                }
            }
        }
            break;
            
        case AVAudioSessionRouteChangeReasonCategoryChange:
            break;
    }
}

- (void)audioInterruption:(NSNotification *)noti {
    if (self.playing == false) return;
    
    NSDictionary *info = noti.userInfo;
    AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self pause];
    } else {
        AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (options == AVAudioSessionInterruptionOptionShouldResume) {
            [self resume];
        }
    }
}


#pragma mark - <来电监听>
- (void)setupCallCenter {
    _callCenter = [[CTCallCenter alloc] init];
    @weakify(self);
    _callCenter.callEventHandler = ^(CTCall* call){
        @strongify(self);
        if([call.callState isEqualToString:CTCallStateDisconnected]) {
            ///电话结束或挂断电话
            [self callListenerMute:NO];
        } else if([call.callState isEqualToString:CTCallStateConnected]) {
            [self callListenerMute:YES];
        } else if([call.callState isEqualToString:CTCallStateIncoming]) {
            [self callListenerMute:YES];
        } else if([call.callState isEqualToString:CTCallStateDialing]) {
            [self callListenerMute:YES];
        } else {
        }
    };
}

- (void)callListenerMute:(BOOL)mute {
    if (self.playing == false) return;
    if (mute) {
        [self pause];
    }else {
        [self resume];
    }
}


- (AudioCache *)audioCache {
    if (!_audioCache) {
        _audioCache = [[AudioCache alloc]init];
    }
    return _audioCache;
}

// 叉掉后，操作再加到父视图上
- (void)canAddAudioCompent {
    if ([self isDescendantOfView] == false) {
        [self ifFloatingAudioView:true];
        [self updateTheSameAudio];
        [self.managerView animateWithDuration:0 show:false];
    }
}

- (void)ifFloatingAudioView:(BOOL)b {
    TTVAudioManagerView *av = self.managerView;
    if (b) {
        if(av.descendantOfView) return;
        [av.viewToShow addSubview:self.managerView];
        [av fixView:CGPointMake(0, ScreenH) animations:false];
    }else {
        self.notTheSameAudio = true;
        [av removeFromSuperview];
    }
}

#pragma mark - 浮动框进入视频详情页和直播详情页隐藏，停止播放音频

- (void)canCtrToViewHidden:(BOOL)b {
    if (self.isDescendantOfView == false)return;
    if (b) {
        self.managerView.hidden = b;
        [self pause];
        [self.managerView showPuase:true];
    }else {
        self.managerView.hidden = b;
    }
}

- (BOOL)isDescendantOfView {
    BOOL descendant = [self.managerView descendantOfView];
    return descendant ;
}


- (void)updateInfo:(id)model{
    self.audioNews = model;
    [self.managerView updateInfo:model];
}

- (NSInteger)findIndexOfSong:(AudioListModel *)audio {
    __block NSInteger index = NSNotFound;
    if (self.songList.count>0 ) {
        [self.songList enumerateObjectsUsingBlock:^(AudioListModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if([obj.pk isEqualToString:audio.pk]) {index = idx;obj.noLogin = audio.noLogin; *stop = YES;}
        }];
        if(index == NSNotFound) { index =0, [self.songList insertObject:audio atIndex:index];}
    }else {
        index = 0;
        self.songList = [NSMutableArray arrayWithArray:@[audio]];
    }
    return index;
}


#pragma mark - 单集播放
- (void)playSingleAudio:(AudioListModel *)audio {
    if (!audio) return;
    [self reportedDuration];
    NSInteger index = [self findIndexOfSong:audio];
    [self playSongAtIndex:index];
}

#pragma mark - 电台播放，不缓存

- (void)playRadio:(AudioListModel *)audio  {
    if (!audio) return;
    [self reportedDuration];
    if ([self checkCurrentSong:audio]) {
        [self ifFloatingAudioView:true];
        self.currentSong = audio;
        self.currentSongIndex = [self findIndexOfSong:audio];
        [self updateInfo:audio];
        
        [self fetchNewSong:audio];
    }
}


- (void)start:(NSString*)url{
    NSString* playUrl = url.length == 0 ? self.playUrl : url;
    if (self.audioPlayer) {
        [self.audioPlayer destory];
    }
    
    if (self.songList.count<=0) self.currentSongIndex  = 0;
    self.timeLength = [[NSDate date] timeIntervalSince1970];
    
    #if 0
        playUrl =  @"http://audio.cos.xmcdn.com/group87/M01/37/C7/wKg5IV75xc_hQC8KAAe05eIl23g627.mp3";
    #endif
    
    TTVAudioPlayer* audioPlayer = [TTVAudioPlayer playerWithURL:playUrl];
    _audioPlayer = audioPlayer;
    self.playUrl = playUrl;

    if ([self.audioNews isKindOfClass:AudioListModel.class]) {
        AudioListModel* news = self.audioNews;
        self.title = news.title.length >0 ? news.title:@"";
    }
    [audioPlayer play];
    
    [self setupAudioListen];
    [self.managerView hideMask];
    
    @weakify(self);
    [RACObserve(self.audioPlayer, audioStatus) subscribeNext:^(NSNumber* x) {
        @strongify(self);
        TTVVAudioStatus status = x.integerValue;
       // DLog(@"status======>%ld ",status);
        if (status == TTVVAudioStatusPlaying && self.needSeekToSecond >0) {// TTVVAudioStatusReady
            [self.audioPlayer seekTo:self.needSeekToSecond];
            self.needSeekToSecond = 0;
        }

        if (status == TTVVAudioStatusPlaying) {
            if(self.canForcedToPlay){[self.audioPlayer resume]; self.canForcedToPlay = false;self.onOutCallBack = nil;}//[self.managerView showPuase:false];
            if(self.onOutCallBack) self.onOutCallBack();
        }
        
        if(status == TTVVAudioStatusError) { self.onOutCallBack = nil;self.needSeekToSecond = 0;}
        
        if (status == TTVVAudioStatusCompleted) {//status == TTVVAudioStatusStop
            self.curTime = 0;
            [self playNext];
            [self canPlayNow];
        }
        
        BOOL check = false;
        if (self.audioPlayer.isLive) {
            check = (status == TTVVAudioStatusReconnecting ||
                     status == TTVVAudioStatusCaching);
        }else {
           check = (status == TTVVAudioStatusReconnecting ||
                    status == TTVVAudioStatusCaching ||
                    status == TTVVAudioStatusNone||
                    status == TTVVAudioStatusReady);
        }

        if (check) {
            [self.managerView startAnimating];
        }else {
            [self.managerView stopAnimating];
        }
    }];
    
    if (self.displosable) [self.displosable dispose];
    self.displosable =  [[[NSNotificationCenter defaultCenter] rac_addObserverForName:UIApplicationWillEnterForegroundNotification object:nil]
                         subscribeNext:^(NSNotification * _Nullable x)
                         {
        @strongify(self);
        if (![self.audioPlayer respondsToSelector:@selector(isPlaying)]) return ;
        BOOL check = self.audioPlayer.isPlaying ==false && self.isLive == false;
        if (check) {
            [self pause];
            self.audioPlayer.audioStatus = TTVVAudioStatusPause;
            [self.managerView stopAnimating];
        }
    }];
}

- (void)stop{
    [self.audioPlayer destory];
}

- (void)pause{
    [self.audioPlayer pause];
    [self reportedDuration];
}

- (void)resume{
    if ([self noLoginPlay]) return;
    
    [self assignTimeLength];
    if(self.audioStatus == TTVVAudioStatusError || self.currentSong.audioUrl.length ==0 ) {
        [self playSingleAudio:self.currentSong];
    }else {
        [self.audioPlayer resume];
    }
}

- (void)seekTo:(double)sec{
    if ([self noLoginPlay]) return;
    
    [self.audioPlayer seekTo:sec];
    if (self.audioPlayer.playing ==NO) [self resume];
//  [self postPlayingCenterfication:self.headerView.coverImage];
}

- (BOOL)noLoginPlay {
    BOOL can = self.currentSong.noLogin;
    if (can) {
        @weakify(self);
        [TTVJumpManager presentLoginVCFrom:[UIViewController ttv_topViewController]
                              dismissBlock:nil
                              successBlock:^{
            @strongify(self);
            BOOL login = [TTVUserInfo sharedTTVUserInfo].isLogin;
            if (login) {
                self.currentSong.noLogin = login;
                [self playSingleAudio:self.currentSong];
            }
        }];
    }
    return can;
}



- (BOOL)isLive{
    return [self.audioPlayer isLive];
}

- (TTVVAudioStatus)audioStatus{
    return self.audioPlayer.audioStatus;
}


- (void)changeAction{
    TTVAudioManager* manager = self;
    if (manager.playing) {
        if (manager.totalTime == manager.curTime && [manager isLive] == false) {
            [manager stop];
        }
        else{
            [manager pause];
            manager.audioPlayer.audioStatus = TTVVAudioStatusPause;
        }
    }
    else{
        if (manager.audioStatus == TTVVAudioStatusCompleted ||manager.audioStatus == TTVVAudioStatusError) {
            if ([self noLoginPlay]) return;
            [self playSingleAudio:self.currentSong];
        }
        else{
            [manager resume];
        }
    }
}

- (void)updateTheSameAudio {
    self.notTheSameAudio = false;
}

- (BOOL)isSameAudio {
    NSString* payingSid = nil;
//    UIViewController* vc = [UIViewController getCurrentViewController];
//    if ([vc isKindOfClass:TTVAudioProgramListViewController.class]) {
//        TTVAudioProgramListViewController* audioDetailsVC = vc;
//        topViewSid =  audioDetailsVC.newsModel.sid;
//    }
    
    if (self.notTheSameAudio) {
        self.notTheSameAudio = false;
        return  false;
    }
    
    if([self.audioNews respondsToSelector:@selector(sid)]){
       //  payingSid = [self.audioNews sid];
     }
     
    if ([self.newsDetail.sid isEqualToString:payingSid] && self.playUrl.length >0) {
        return true;
    }

    return false;
}

- (void)assignmentToNilNewsId {
//    AudioListModel *thisNews = self.audioNews;
//    if([thisNews respondsToSelector:@selector(sid)]) {
//        thisNews.sid = nil;
//    }
}



- (void)playNext {
    NSInteger currentSongIndex  = self.currentSongIndex + 1;
    
    if (self.audioPlayer == nil) return;
    if (self.managerView.canForward == false) {[self reportedDuration];return;}
    
    [self canPlayNow:currentSongIndex];
    if(currentSongIndex > self.songList.count-1) {
//      self.curTime = 0;
        return;                 
    }
    
    [self pause];
    [self onPlaySongAtIndex:currentSongIndex];
}

- (void)playPrev {
    if (self.audioPlayer == nil) return;
    if (self.managerView.canBackward == false)  return;

    NSInteger currentSongIndex  = self.currentSongIndex - 1;
    [self canPlayNow:currentSongIndex];
    
    if(currentSongIndex < 0) {
        return;
    }
    
    [self pause];
    [self onPlaySongAtIndex:currentSongIndex];
}


- (void)playSongAtIndex:(NSInteger)index {
    if (index >= self.songList.count || index < 0) return;
   
    AudioListModel *currentSong = self.songList[index];
    if ([self checkCurrentSong:currentSong]) {
        [self ifFloatingAudioView:true];
        
        self.currentSong = currentSong;
    //  [self postSummerTextNotification:currentSong];
        self.currentSongIndex = index;
        [self updateInfo:currentSong];
        
        [self fetchNewSong:currentSong ];
    }
}

- (void)fetchNewSong:(AudioListModel *)song{
    @weakify(self);
    if(song.viewStyle == TTVViewStyleAlubm) {
        [self fetchAudioSong:song retBlock:^(NSString *url) {
            @strongify(self);
            if (url)song.audioUrl = url;
            [self start:song.audioUrl];
            [self canPlayNow];
        }];
        
    }else if (song.viewStyle == TTVViewStyleRadio) {
        [self programRetBlock:^(NSString *url) {
            @strongify(self);
            if (url)self.currentSong.audioUrl = url;
            AudioListModel *am = [self updateAudio:self.currentSong];
            [self start:am.audioUrl];
            [self canPlayNow];
        }];
    }else {
        [self start:song.audioUrl];
        [self canPlayNow];
    }
}


//[0,n)
- (void)canPlayNow:(NSInteger)currentSongIndex {
    NSInteger index = currentSongIndex;
    
    [self.managerView enableButton];

    if (self.songList.count ==0) {
        self.currentSongIndex = 0;
        [self.managerView banNextButton];
        [self.managerView banPrevButton];
    }

    if (index == self.songList.count-1) {
        self.currentSongIndex = index;
        [self.managerView banNextButton];
    }

    if (index == 0) {
        self.currentSongIndex = 0;
        [self.managerView banPrevButton];
    }
}


- (void)canPlayNow  {
    [self canPlayNow:self.currentSongIndex];
}


#pragma mark - UI Lazy loading.UI懒加载
- (TTVAudioManagerView*)managerView{
    if (!_managerView) {
        _managerView = [[TTVAudioManagerView alloc] init];
        _managerView.size = [TTVAudioManagerView ShowSize];
        _managerView.tag = kManagerViewTag;
    }
    return _managerView;
}

- (CGFloat)manageViewHeight {
    return  self.managerView.size.height;
}


- (CGFloat)subViewBottomOffset {
    BOOL descendant = [self isDescendantOfView];
 // CGFloat offset = descendant ? ((IsiPhoneX ? 20:0) + self.manageViewHeight):0;
    CGFloat offset = descendant ? self.manageViewHeight:0;
    return offset;
}

#pragma mark - SDK provides methods.SDK提供方法

- (void)onPlaySongAtIndex:(NSInteger)index {
    if (index >= self.songList.count || index < 0) return;

    AudioListModel *currentSong = self.songList[index];
    if ([self checkCurrentSong:currentSong]) {
        [self ifFloatingAudioView:true];
        self.currentSong = currentSong;
        self.currentSongIndex = index;
//        [self postChangeAudioNotification:self.songList[self.currentSongIndex]];
//        [self postSummerTextNotification:currentSong];
        
        [self updateInfo:currentSong];
        
        [self fetchNewSong:currentSong];
    }
}

- (BOOL)checkCurrentSong:(AudioListModel *)currentSong  {
    BOOL c = [currentSong isKindOfClass:AudioListModel.class] ;
    
  // BOOL c = [currentSong isKindOfClass:AudioListModel.class] && len > 0;
  // if (len<=0) [UIView MakeToast:@"播放地址不合法～"];
    
    return c;
}


#pragma mark - setupAudioListen

- (void)disposeAudioListen {
    if (self.handler)
        [self.handler dispose];
}

- (void)setupAudioListen {
    [self disposeAudioListen];
   // self.needBanToListen = false;
    TTVAudioManager* manager = self;
    @weakify(self);
    __block double duration = 0;
    __block BOOL hasPostNotifiaction  = false;
    NSMutableArray<RACSignal*>* ary = [NSMutableArray array];
    [ary addObject:RACObserve(self.audioPlayer, current)];
    [ary addObject:RACObserve(self.audioPlayer, duration)];
    [ary addObject:RACObserve(self.audioPlayer, playing)];
  //  [ary addObject:RACObserve(self.managerView, coverImage)];
    
   self.handler = [[RACSignal merge:ary] subscribeNext:^(id  _Nullable x) {
        @strongify(self);
       self.curTime = self.audioPlayer.current;
       self.totalTime = self.audioPlayer.duration;
       self.playing = self.audioPlayer.playing ;
       [self.managerView updataSlider:self.curTime totalTime:self.totalTime isPlaying:self.playing isLive:false];//manager.isLive
       
       double diff = self.curTime - self.audioCache.seektime;
       TTVViewStyle style = self.currentSong.viewStyle;
       if ((diff >=3.5 || diff <= -3.5) && style !=TTVViewStyleRadio && style !=TTVViewStyleRadioAlbum )
           [self saveSeekTime:self.curTime];

//        UIImage *coverImage = self.managerView.coverImage;
//        BOOL nowCond = manager.isLive && coverImage && hasPostNotifiaction==false;
//        BOOL vodCond = totalTime != duration && totalTime !=0 && coverImage;
//        BOOL over = curTime == 0 && totalTime > 0;
//        if (nowCond) {
//            hasPostNotifiaction = true;
//            [self postNotifictionObj:coverImage];
//        }else if(vodCond ) {
//            hasPostNotifiaction = false;
//            [self postNotifictionObj:coverImage];
//        }else if(over) {
//           [self postNotifictionObj:coverImage];
//        }
//        if (coverImage) duration = totalTime;
    }];
}


//- (void)postPlayingCenterfication:(UIImage *)obj {
//    [[NSNotificationCenter defaultCenter]
//     postNotificationName:TTVConfigNowPlayingCenterfication
//               object:obj];
//}
//
//- (void)postChangeAudioNotification:(TTVAudioDetailsCellModel *)object {
//     [[NSNotificationCenter defaultCenter] postNotificationName:
//      TTVNotificationAudioDetailsChangeAudio
//      object:object];
//}

//- (void)postSummerTextNotification:(AudioListModel *)thisNews {
//
//}

- (void)saveSeekTime:(double)curTime {
    self.audioCache.model = self.currentSong;
    self.audioCache.seektime = curTime;
    [TTVCacheDisk cacheDiskSetObject:self.audioCache forKey:kTTVDataCacheSongListSeekTime];
}

- (void)setSongList:(NSArray<AudioListModel *> *)songList {
    _songList = songList;
    [TTVCacheDisk cacheDiskSetObject:songList forKey:kTTVDataCacheSongListRecordType];
}

#pragma mark - cache

- (NSArray<AudioListModel *> *)cacheSongList {
    NSArray * songs = (NSArray*)[TTVCacheDisk objectForKey:kTTVDataCacheSongListRecordType];
    return songs;
}

- (AudioCache *)cacheSeekTime {
    AudioCache * c = (AudioCache*)[TTVCacheDisk objectForKey:kTTVDataCacheSongListSeekTime];
    return c;
}


// 上报收听时长
- (void)reportedDuration {
    if (![TTVUserInfo sharedTTVUserInfo].isLogin) return;
    if (self.timeLength ==0) return;
    
    double currentTimeLenth = self.timeLength;
    [self assignZeroTimeLength];
    double currentTime  = [NSDate currentIntervalMS];
    double diff= [[NSDate date] timeIntervalSince1970] - currentTimeLenth;
    NSString *msgId = [NSString stringWithFormat:@"%0.f%",currentTime];
    NSString *len = [NSString stringWithFormat:@"%0.f",diff];
    NSInteger objectType = 4;
    if (self.currentSong.viewStyle ==TTVViewStyleAlubm ) {
        objectType = 4;
    }else if (self.currentSong.viewStyle ==TTVViewStyleRadio) {
        objectType = 45;
    }else if (self.currentSong.viewStyle ==TTVViewStyleRadioAlbum) {
        objectType = 8;
    }
    @weakify(self);
    [[TTVApiService audiowatchTimeSid:self.currentSong.pk messageId:msgId timeLength:len objectType:objectType] subscribeNext:^(id  _Nullable x) {
    
    } error:^(NSError * _Nullable error) {
        @strongify(self);
        self.timeLength = currentTimeLenth;
    }];
}

- (void)assignZeroTimeLength {
    self.timeLength = 0;
}

- (void)assignTimeLength {
    if (self.timeLength ==0)
        self.timeLength = [[NSDate date] timeIntervalSince1970];
}

#pragma mark - tv

- (void)programRetBlock:(void (^)(NSString * url))retBlock{
    @weakify(self);
    [TTVAudioAlbumModel fetchProgram:self.newsDetail callBackBlock:^(NSString *audio) {
        @strongify(self);
        retBlock(audio);
    }];
}

#pragma mark - newsContent

- (void)fetchAudioSong:(AudioListModel *)currentSong retBlock:(void (^)(NSString * url))retBlock {
    __block void (^reqLoginBlock)() = nil;
    __block void (^reqAudioBlock)() = nil;
    
    @weakify(self);
    reqAudioBlock = ^{
        TTVNewsDetailModel *nm = TTVNewsDetailModel.new;
        nm.sid = currentSong.pk;
        nm.channelId = @"0";
        [TTVAudioAlbumModel fetchSingleAudio:nm callBackBlock:^(TTVSingleVideoModel *vidoe) {
            @strongify(self);
            TTVThisNews *news = vidoe.tTVThisNews;
            TTVVideoUrlModel* videoModel = [TTVVideoUrlModel mj_objectWithKeyValues:[[NSString dictionaryWithJsonString:news.videoUrl] dictionaryForKey:@"source"]];
            NSString *audioUrl = [videoModel findVideoUrl];
            
            if(currentSong.noLogin && audioUrl.length <=0) {
                if(self.onOutCallBack) self.onOutCallBack();
                self.needSeekToSecond = 0;
                [self canPlayNow];
                
            }else if(audioUrl.length >0) {
                retBlock(audioUrl);
            }else if (![TTVUserInfo sharedTTVUserInfo].isLogin) {
                reqLoginBlock();
            }else {
                retBlock(audioUrl);
            }
        }];
    };
    
    reqLoginBlock = ^{
        [TTVJumpManager presentLoginVCFrom:[UIViewController ttv_topViewController]
                              dismissBlock:nil
                              successBlock:reqAudioBlock];
    };
    
    reqAudioBlock();
}

- (AudioListModel *)updateAudio:(AudioListModel *)au {
    NSString *url = [self calcUrl:au];
    au.audioUrl = url;
    au.viewStyle = TTVViewStyleRadio;
    
    return au;
}

- (NSString*)calcUrl:(AudioListModel*)video  {
    if(video.audioUrl.length <=0) return @"";
    
    NSString* liveUrl = video.audioUrl;
    long long timestamp = [NSDate timestamp];
    long long timeSp = video.updateTime + 3600 * 6 * 1000;
    NSString *parameter = @"";
    if (timestamp >= video.updateTime && timestamp <= video.endTime) {
        //当前节目
        parameter = @"";
    
    } else if (timestamp > video.endTime) {
        //旧节目
        parameter = [NSString stringWithFormat:@"lhs_start_unix_ms_0=%0.lf&aliyunols=on&lhs_vodend_unix_ms_0=%lld",video.updateTime,timeSp];
        
    }else if (timestamp < video.updateTime){
        //节目未开始
        parameter = @"";
    }
    
    if ([liveUrl containsString:@"?"] && parameter.length >0) {
        liveUrl = [NSString stringWithFormat:@"%@&%@",liveUrl,parameter];
        
    }else if(parameter.length >0){
        liveUrl = [NSString stringWithFormat:@"%@?%@",liveUrl,parameter];
    }
    return liveUrl;
}

@end
