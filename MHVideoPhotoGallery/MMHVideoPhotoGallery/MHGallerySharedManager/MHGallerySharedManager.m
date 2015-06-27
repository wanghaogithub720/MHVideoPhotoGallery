//
//  MHGallerySharedManager.m
//  MHVideoPhotoGallery
//
//  Created by Mario Hahn on 01.04.14.
//  Copyright (c) 2014 Mario Hahn. All rights reserved.
//

#import "MHGallerySharedManager.h"
#import "MHGallerySharedManagerPrivate.h"

@implementation MHGallerySharedManager

+ (MHGallerySharedManager *)sharedManager{
    static MHGallerySharedManager *sharedManagerInstance = nil;
    static dispatch_once_t onceQueue;
    dispatch_once(&onceQueue, ^{
        sharedManagerInstance = self.new;
    });
    return sharedManagerInstance;
}

-(void)getImageFromAssetLibrary:(NSString*)urlString
                      assetType:(MHAssetImageType)type
                   successBlock:(void (^)(UIImage *image,NSError *error))succeedBlock{
    
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void){
        ALAssetsLibrary *assetslibrary = ALAssetsLibrary.new;
        [assetslibrary assetForURL:[NSURL URLWithString:urlString]
                       resultBlock:^(ALAsset *asset){
                           
                           if (type == MHAssetImageTypeThumb) {
                               dispatch_sync(dispatch_get_main_queue(), ^(void){
                                   UIImage *image = [UIImage.alloc initWithCGImage:asset.thumbnail];
                                   succeedBlock(image,nil);
                               });
                           }else{
                               ALAssetRepresentation *rep = asset.defaultRepresentation;
                               CGImageRef iref = rep.fullScreenImage;
                               if (iref) {
                                   dispatch_sync(dispatch_get_main_queue(), ^(void){
                                       UIImage *image = [UIImage.alloc initWithCGImage:iref];
                                       succeedBlock(image,nil);
                                   });
                               }
                           }
                       }
                      failureBlock:^(NSError *error) {
                          dispatch_sync(dispatch_get_main_queue(), ^(void){
                              succeedBlock(nil,error);
                          });
                      }];
    });
}

-(BOOL)isUIViewControllerBasedStatusBarAppearance{
    NSNumber *isUIVCBasedStatusBarAppearance = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UIViewControllerBasedStatusBarAppearance"];
    if (isUIVCBasedStatusBarAppearance) {
        return  isUIVCBasedStatusBarAppearance.boolValue;
    }
    return YES;
}

-(NSString*)languageIdentifier{
    static NSString *applicationLanguageIdentifier;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        applicationLanguageIdentifier = @"en";
        NSArray *preferredLocalizations = NSBundle.mainBundle.preferredLocalizations;
        if (preferredLocalizations.count > 0)
            applicationLanguageIdentifier = [NSLocale canonicalLanguageIdentifierFromString:preferredLocalizations[0]] ?: applicationLanguageIdentifier;
    });
    return applicationLanguageIdentifier;
}

-(void)getYoutubeURLforMediaPlayer:(NSString*)URL
                      successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    NSString *videoID = [[URL componentsSeparatedByString:@"?v="] lastObject];
    NSURL *videoInfoURL = [NSURL URLWithString:[NSString stringWithFormat:MHYoutubePlayBaseURL, videoID ?: @"", [self languageIdentifier]]];
    NSMutableURLRequest *httpRequest = [[NSMutableURLRequest alloc] initWithURL:videoInfoURL
                                                                    cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                                timeoutInterval:10];
    [httpRequest setValue:[self languageIdentifier] forHTTPHeaderField:@"Accept-Language"];
    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:NSOperationQueue.new
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               dispatch_async(dispatch_get_main_queue(), ^(void){
                                   NSURL *playURL = [self getYoutubeURLWithData:data];
                                   if (playURL) {
                                       succeedBlock(playURL,nil);
                                   }else{
                                       succeedBlock(nil,nil);
                                   }
                               });
                           }];
}

- (NSURL *)getYoutubeURLWithData:(NSData *)data{
    NSString *videoData = [NSString.alloc initWithData:data encoding:NSASCIIStringEncoding];
    
    NSDictionary *video = MHDictionaryForQueryString(videoData);
    NSArray *videoURLS = [video[@"url_encoded_fmt_stream_map"] componentsSeparatedByString:@","];
    NSMutableDictionary *streamURLs = NSMutableDictionary.new;
    for (NSString *videoURL in videoURLS){
        NSDictionary *stream = MHDictionaryForQueryString(videoURL);
        NSString *typeString = stream[@"type"];
        NSString *urlString = stream[@"url"];
        if (urlString && [AVURLAsset isPlayableExtendedMIMEType:typeString]) {
            NSURL *streamURL = [NSURL URLWithString:urlString];
            NSString *sig = stream[@"sig"];
            if (sig){
                streamURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@&signature=%@", urlString, sig]];
            }
            if ([[MHDictionaryForQueryString(streamURL.query) allKeys] containsObject:@"signature"]){
                streamURLs[@([stream[@"itag"] integerValue])] = streamURL;
            }
        }
    }
    if (self.youtubeVideoQuality == MHYoutubeVideoQualityHD720) {
        if (streamURLs[@(22)]) {
            return streamURLs[@(22)];
        }
    }
    
    if (self.youtubeVideoQuality == MHYoutubeVideoQualityHD720 || self.youtubeVideoQuality == MHYoutubeVideoQualityMedium) {
        if (streamURLs[@(18)]) {
            return streamURLs[@(18)];
        }
    }
    if(self.youtubeVideoQuality == MHYoutubeVideoQualitySmall){
        if (streamURLs[@(36)]) {
            return streamURLs[@(36)];
        }
    }
    
    return nil;
}

-(void)getURLForMediaPlayer:(NSString*)URLString
               successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    if ([URLString rangeOfString:@"vimeo.com"].location != NSNotFound) {
        [self getVimeoURLforMediaPlayer:URLString successBlock:^(NSURL *URL, NSError *error) {
            succeedBlock(URL,error);
        }];
    }else if([URLString rangeOfString:@"youtube.com"].location != NSNotFound) {
        [self getYoutubeURLforMediaPlayer:URLString successBlock:^(NSURL *URL, NSError *error) {
            succeedBlock(URL,error);
        }];
    }else{
        succeedBlock([NSURL URLWithString:URLString],nil);
    }
    
    
}


-(void)getVimeoURLforMediaPlayer:(NSString*)URL
                    successBlock:(void (^)(NSURL *URL,NSError *error))succeedBlock{
    
    NSString *videoID = [[URL componentsSeparatedByString:@"/"] lastObject];
    NSURL *vimdeoURL= [NSURL URLWithString:[NSString stringWithFormat:MHVimeoVideoBaseURL, videoID]];
    
    NSMutableURLRequest *httpRequest = [NSMutableURLRequest requestWithURL:vimdeoURL
                                                               cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                           timeoutInterval:10];
    
    [httpRequest setValue:@"application/json"
       forHTTPHeaderField:@"Content-Type"];
    
    [NSURLConnection sendAsynchronousRequest:httpRequest
                                       queue:NSOperationQueue.new
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               if (!connectionError) {
                                   NSError *error;
                                   
                                   NSDictionary *jsonData = [NSJSONSerialization JSONObjectWithData:data
                                                                                            options:NSJSONReadingAllowFragments
                                                                                              error:&error];
                                   dispatch_async(dispatch_get_main_queue(), ^(void){
                                       NSDictionary *filesInfo = [jsonData valueForKeyPath:@"request.files.h264"];
                                       if (!filesInfo) {
                                           succeedBlock(nil,nil);
                                       }
                                       NSString *quality = NSString.new;
                                       if (self.vimeoVideoQuality == MHVimeoVideoQualityHD) {
                                           quality = @"hd";
                                           if(!filesInfo[quality]){
                                               quality = @"sd";
                                           }
                                       } else if (self.vimeoVideoQuality == MHVimeoVideoQualityMobile){
                                           quality = @"mobile";
                                       }else if(self.vimeoVideoQuality == MHVimeoVideoQualitySD){
                                           quality = @"sd";
                                       }
                                       NSDictionary *videoInfo =filesInfo[quality];
                                       if (!videoInfo[@"url"]) {
                                           succeedBlock(nil,nil);
                                       }
                                       succeedBlock([NSURL URLWithString:videoInfo[@"url"]],nil);
                                   });
                               }else{
                                   succeedBlock(nil,connectionError);
                               }
                               
                           }];
}

-(void)setObjectToUserDefaults:(NSMutableDictionary*)dict{
    [NSUserDefaults.standardUserDefaults setObject:dict forKey:MHGalleryDurationData];
    [NSUserDefaults.standardUserDefaults synchronize];
}
-(NSMutableDictionary*)durationDict{
    return [NSMutableDictionary.alloc initWithDictionary:[NSUserDefaults.standardUserDefaults objectForKey:MHGalleryDurationData]];
}




-(void)getMHGalleryObjectsForYoutubeChannel:(NSString*)channelName
                                  withTitle:(BOOL)withTitle
                               successBlock:(void (^)(NSArray *MHGalleryObjects,NSError *error))succeedBlock{
    NSMutableURLRequest *httpRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:MHYoutubeChannel,channelName]] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:5];
    [NSURLConnection sendAsynchronousRequest:httpRequest queue:NSOperationQueue.new completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
        if (connectionError) {
            succeedBlock(nil,connectionError);
            
        }else{
            dispatch_sync(dispatch_get_main_queue(), ^{
                
                NSError *error = nil;
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data
                                                                     options: NSJSONReadingMutableContainers
                                                                       error: &error];
                if (!error) {
                    NSMutableArray *galleryData = NSMutableArray.new;
                    for (NSDictionary *dictionary in dict[@"feed"][@"entry"]) {
                        NSString *string = [dictionary[@"link"] firstObject][@"href"];
                        
                        string = [string stringByReplacingOccurrencesOfString:@"&feature=youtube_gdata" withString:@""];
                        MHGalleryItem *item = [MHGalleryItem itemWithURL:string galleryType:MHGalleryTypeVideo];
                        if (withTitle) {
                            item.descriptionString = dictionary[@"title"][@"$t"];
                        }
                        [galleryData addObject:item];
                    }
                    succeedBlock(galleryData,nil);
                }else{
                    succeedBlock(nil,error);
                }
            });
        }
    }];
}


+(NSString*)stringForMinutesAndSeconds:(NSInteger)seconds
                              addMinus:(BOOL)addMinus{
    
    NSNumber *minutesNumber = @(seconds / 60);
    NSNumber *secondsNumber = @(seconds % 60);
    
    NSString *string = [NSString stringWithFormat:@"%@:%@",[MHNumberFormatterVideo() stringFromNumber:minutesNumber],[MHNumberFormatterVideo() stringFromNumber:secondsNumber]];
    if (addMinus) {
        return [NSString stringWithFormat:@"-%@",string];
    }
    return string;
}

@end
