//
//  TTVAudioManager.h
//  TouchTV
//
//  Created by 周启睿 on 2020/2/7.
//  Copyright © 2020 TouchTV. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TTVAudioManagerView.h"
#import "TTVAudioPlayer.h"
#import "TTVNewsDetailModel.h"
#import "TTVAudioAlbumModel.h"

NS_ASSUME_NONNULL_BEGIN
@interface TTVAudioManager : NSObject

singleton_interface(TTVAudioManager);
@property (nonatomic, strong) TTVAudioPlayer *audioPlayer;
@property (nonatomic, assign) double  curTime;
@property (nonatomic, assign) double  totalTime;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) TTVNewsDetailModel *newsDetail;
@property (nonatomic, strong) TTVAudioManagerView  *managerView;
@property (nonatomic, strong) NSMutableArray <AudioListModel*> *songList;
@property (nonatomic, assign) NSUInteger needSeekToSecond;
@property (nonatomic, assign) BOOL canForcedToPlay;
@property (nonatomic,   copy) void (^onOutCallBack)();

- (BOOL)isLive;
- (void)canPlayNow;
- (void)seekTo:(double)sec;
- (void)changeAction;
- (void)pause;
- (void)resume;
- (void)playNext;
- (void)playPrev;

- (void)playSongAtIndex:(NSInteger)index;
//单集播放
- (void)playSingleAudio:(AudioListModel *)audio;
//电台播放，不缓存
- (void)playRadio:(AudioListModel *)audio;
// add subview
- (void)ifFloatingAudioView:(BOOL)b;
// Hide
- (void)canCtrToViewHidden:(BOOL)b;
- (BOOL)isDescendantOfView ;
- (CGFloat)subViewBottomOffset ;
- (void)reportedDuration ;
#pragma mark - cache

- (NSArray<AudioListModel *> *)cacheSongList;
- (AudioCache *)cacheSeekTime;

@end

NS_ASSUME_NONNULL_END
