/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBWebServer.h"

#import <RoutingHTTPServer/RoutingConnection.h>
#import <RoutingHTTPServer/RoutingHTTPServer.h>

#import "FBCommandHandler.h"
#import "FBErrorBuilder.h"
#import "FBExceptionHandler.h"
#import "FBMjpegServer.h"
#import "FBRouteRequest.h"
#import "FBRuntimeUtils.h"
#import "FBSession.h"
#import "FBTCPSocket.h"
#import "FBUnknownCommands.h"
#import "FBConfiguration.h"
#import "FBLogger.h"

#import "XCUIDevice+FBHelpers.h"

static NSString *const FBServerURLBeginMarker = @"Inspector URL Here->";
static NSString *const FBServerURLEndMarker = @"/Inspector";

@interface FBHTTPConnection : RoutingConnection
@end

@implementation FBHTTPConnection

- (void)handleResourceNotFound
{
  [FBLogger logFmt:@"Received request for %@ which we do not handle", self.requestURI];
  [super handleResourceNotFound];
}

@end


@interface FBWebServer ()
@property (nonatomic, strong) FBExceptionHandler *exceptionHandler;
@property (nonatomic, strong) RoutingHTTPServer *server;
@property (atomic, assign) BOOL keepAlive;
@property (nonatomic, nullable) FBTCPSocket *screenshotsBroadcaster;
@end

@implementation FBWebServer

+ (NSArray<Class<FBCommandHandler>> *)collectCommandHandlerClasses
{
  NSArray *handlersClasses = FBClassesThatConformsToProtocol(@protocol(FBCommandHandler));
  NSMutableArray *handlers = [NSMutableArray array];
  for (Class aClass in handlersClasses) {
    if ([aClass respondsToSelector:@selector(shouldRegisterAutomatically)]) {
      if (![aClass shouldRegisterAutomatically]) {
        continue;
      }
    }
    [handlers addObject:aClass];
  }
  return handlers.copy;
}

- (void)startServing
{
  [FBLogger logFmt:@"Built at %s %s", __DATE__, __TIME__];
  self.exceptionHandler = [FBExceptionHandler new];
  [self startHTTPServer];
  [self initScreenshotsBroadcaster];

  self.keepAlive = YES;
  NSRunLoop *runLoop = [NSRunLoop mainRunLoop];
  while (self.keepAlive &&
         [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
}

- (void)startHTTPServer
{
  self.server = [[RoutingHTTPServer alloc] init];
  [self.server setRouteQueue:dispatch_get_main_queue()];
  [self.server setDefaultHeader:@"Server" value:@"WebDriverAgent/1.0"];
  [self.server setType:@"_http._tcp."];
  [self.server setName:[NSString stringWithFormat:@"%@-%@",@"WebDriverAgent",[[UIDevice currentDevice] name]]];

  // Cross-origin resource sharing problem
  [self.server setDefaultHeader:@"Access-Control-Allow-Origin" value:@"*"];
  [self.server setDefaultHeader:@"Access-Control-Allow-Methods" value:@"*"];
  [self.server setDefaultHeader:@"Access-Control-Allow-Headers" value:@"*"];
  [self.server setConnectionClass:[FBHTTPConnection self]];

  [self registerRouteHandlers:[self.class collectCommandHandlerClasses]];
  [self registerServerKeyRouteHandlers];

  NSRange serverPortRange = FBConfiguration.bindingPortRange;
  NSError *error;
  BOOL serverStarted = NO;

  for (NSUInteger index = 0; index < serverPortRange.length; index++) {
    NSInteger port = serverPortRange.location + index;
    [self.server setPort:(UInt16)port];

    serverStarted = [self attemptToStartServer:self.server onPort:port withError:&error];
    if (serverStarted) {
      break;
    }

    [FBLogger logFmt:@"Failed to start web server on port %ld with error %@", (long)port, [error description]];
  }

  if (!serverStarted) {
    [FBLogger logFmt:@"Last attempt to start web server failed with error %@", [error description]];
    abort();
  }
  [FBLogger logFmt:@"%@http://%@:%d%@", FBServerURLBeginMarker, [XCUIDevice sharedDevice].fb_wifiIPAddress ?: @"localhost", [self.server port], FBServerURLEndMarker];
}

- (void)initScreenshotsBroadcaster
{
  [self readMjpegSettingsFromEnv];
  self.screenshotsBroadcaster = [[FBTCPSocket alloc]
                                 initWithPort:(uint16_t)FBConfiguration.mjpegServerPort];
  self.screenshotsBroadcaster.delegate = [[FBMjpegServer alloc] init];
  NSError *error;
  if (![self.screenshotsBroadcaster startWithError:&error]) {
    [FBLogger logFmt:@"Cannot init screenshots broadcaster service on port %@. Original error: %@", @(FBConfiguration.mjpegServerPort), error.description];
    self.screenshotsBroadcaster = nil;
  }
}

- (void)stopScreenshotsBroadcaster
{
  if (nil == self.screenshotsBroadcaster) {
    return;
  }

  [self.screenshotsBroadcaster stop];
}

- (void)readMjpegSettingsFromEnv
{
  NSDictionary *env = NSProcessInfo.processInfo.environment;
  NSString *scalingFactor = [env objectForKey:@"MJPEG_SCALING_FACTOR"];
  if (scalingFactor != nil && [scalingFactor length] > 0) {
    [FBConfiguration setMjpegScalingFactor:[scalingFactor integerValue]];
  }
  NSString *screenshotQuality = [env objectForKey:@"MJPEG_SERVER_SCREENSHOT_QUALITY"];
  if (screenshotQuality != nil && [screenshotQuality length] > 0) {
    [FBConfiguration setMjpegServerScreenshotQuality:[screenshotQuality integerValue]];
  }
}

- (void)stopServing
{
  [FBSession.activeSession kill];
  [self stopScreenshotsBroadcaster];
  if (self.server.isRunning) {
    [self.server stop:NO];
  }
  self.keepAlive = NO;
}

- (BOOL)attemptToStartServer:(RoutingHTTPServer *)server onPort:(NSInteger)port withError:(NSError **)error
{
  server.port = (UInt16)port;
  NSError *innerError = nil;
  BOOL started = [server start:&innerError];
  if (!started) {
    if (!error) {
      return NO;
    }

    NSString *description = @"Unknown Error when Starting server";
    if ([innerError.domain isEqualToString:NSPOSIXErrorDomain] && innerError.code == EADDRINUSE) {
      description = [NSString stringWithFormat:@"Unable to start web server on port %ld", (long)port];
    }
    return
    [[[[FBErrorBuilder builder]
       withDescription:description]
      withInnerError:innerError]
     buildError:error];
  }
  return YES;
}

- (void)registerRouteHandlers:(NSArray *)commandHandlerClasses
{
  for (Class<FBCommandHandler> commandHandler in commandHandlerClasses) {
    NSArray *routes = [commandHandler routes];
    for (FBRoute *route in routes) {
      [self.server handleMethod:route.verb withPath:route.path block:^(RouteRequest *request, RouteResponse *response) {
        NSDictionary *arguments = [NSJSONSerialization JSONObjectWithData:request.body options:NSJSONReadingMutableContainers error:NULL];
        FBRouteRequest *routeParams = [FBRouteRequest
          routeRequestWithURL:request.url
          parameters:request.params
          arguments:arguments ?: @{}
        ];

        [FBLogger verboseLog:routeParams.description];

        @try {
          [route mountRequest:routeParams intoResponse:response];
        }
        @catch (NSException *exception) {
          [self handleException:exception forResponse:response];
        }
      }];
    }
  }
}

- (NSData *)getDevice {



  NSDictionary* device = [[NSMutableDictionary alloc] init];
  NSDictionary* emptyObj = [[NSDictionary alloc] init];
  NSDictionary* provider = [[NSMutableDictionary alloc] init];
  NSString* uid = [[[UIDevice currentDevice] identifierForVendor] UUIDString];

  [provider setValue:[[UIDevice currentDevice] name] forKey:@"name"];
  [provider setValue:uid forKey:@"channel"];

  NSNumber *yes = [NSNumber numberWithBool:YES];
  NSNumber *no = [NSNumber numberWithBool:NO];

  NSDate* now = [[NSDate alloc] init];
  NSDateFormatter *formatter = [[NSDateFormatter alloc] init] ;
  [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];

  [device setValue:@"abi" forKey:@"arm64"];
  [device setValue:no forKey:@"airplaneMode"];
  [device setValue:emptyObj forKey:@"battery"];
  [device setValue:emptyObj forKey:@"browser"];
  [device setValue:uid forKey:@"channel"];
  [device setValue:@"" forKey:@"cpuPlatform"];
  [device setValue:[formatter stringFromDate:now]  forKey:@"createdAt"];
  [device setValue:@"Apple" forKey:@"manufacturer"];
  [device setValue: [[UIDevice currentDevice] model] forKey:@"model"];
  [device setValue:emptyObj forKey:@"network"];
  [device setValue:@"2.0" forKey:@"openGLESVersion"];
  [device setValue:@"" forKey:@"operator"];
  [device setValue:@"" forKey:@"owner"];
  [device setValue:uid forKey:@"serial"];
  [device setValue:emptyObj forKey:@"phone"];
  [device setValue:@"iOS" forKey:@"platform"];
  [device setValue:@3 forKey:@"status"];
  [device setValue:yes forKey:@"using"];
  [device setValue:[formatter stringFromDate:now] forKey:@"presenceChangedAt"];
  [device setValue:yes forKey:@"present"];
  [device setValue:emptyObj forKey:@"display"];
  [device setValue:[[UIDevice currentDevice] localizedModel] forKey:@"product"];
  [device setValue:provider forKey:@"provider"];
  [device setValue:yes forKey:@"ready"];
  [device setValue:yes forKey:@"remoteConnect"];
  [device setValue:emptyObj forKey:@"sdk"];
  [device setValue:emptyObj forKey:@"display"];
  [device setValue:[[UIDevice currentDevice] systemVersion] forKey:@"version"];


  NSError *error = nil;
  NSData * data = [NSJSONSerialization dataWithJSONObject:device
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:&error];
  if (error) {
    return nil;
  }
  return data;
}



- (NSData *)keyPress:(NSString *)key{
  [FBLogger logFmt:@"keyPress key = %@",key];
  NSDictionary* emptyObj = [[NSDictionary alloc] init];

  if ([key isEqualToString:@"mute"]){
    for(int i = 0 ; i < 20; i ++){
      [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonVolumeDown];
    }
  }else if ([key isEqualToString:@"volume_down"]){
    [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonVolumeDown];
  }else if ([key isEqualToString:@"volume_up"]){
    [[XCUIDevice sharedDevice] pressButton:XCUIDeviceButtonVolumeUp];
  }
  NSError *error = nil;
  NSData * data = [NSJSONSerialization dataWithJSONObject:emptyObj
                                                  options:NSJSONWritingPrettyPrinted
                                                    error:&error];
  if (error) {
    return nil;
  }
  return data;
}


-(UIImage*)imageWithImage: (UIImage*) sourceImage scaledToWidth: (CGFloat) i_width
{
  CGFloat oldWidth = sourceImage.size.width;
  CGFloat scaleFactor = i_width / oldWidth;

  CGFloat newHeight = sourceImage.size.height * scaleFactor;
  CGFloat newWidth = oldWidth * scaleFactor;

  UIGraphicsBeginImageContext(CGSizeMake(newWidth, newHeight));
  [sourceImage drawInRect:CGRectMake(0, 0, newWidth, newHeight)];
  UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
  UIGraphicsEndImageContext();
  return newImage;
}

- (NSData *)screenshot {
  XCUIScreen *mainScreen = [XCUIScreen mainScreen];
  UIImage *image =  [[mainScreen screenshot] image];
  image = [self imageWithImage:image scaledToWidth:480];
  NSData* screenshotData = (NSData *)UIImageJPEGRepresentation(image, 1);
  return  [screenshotData base64EncodedDataWithOptions:NSDataBase64EncodingEndLineWithLineFeed];
}


- (void)handleException:(NSException *)exception forResponse:(RouteResponse *)response
{
  if ([self.exceptionHandler handleException:exception forResponse:response]) {
    return;
  }
  id<FBResponsePayload> payload = FBResponseWithErrorFormat(@"%@\n\n%@", exception.description, exception.callStackSymbols);
  [payload dispatchWithResponse:response];
}

- (void)registerServerKeyRouteHandlers
{
  [self.server get:@"/health" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithString:@"I-AM-ALIVE"];
  }];

  [self.server get:@"/wda/shutdown" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithString:@"Shutting down"];
    [self.delegate webServerDidRequestShutdown:self];
  }];

  [self.server get:@"/device" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithData: [self getDevice]];
  }];

  [self.server post:@"/keyPress" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithData: [self keyPress:[request param:@"key"]]];
  }];

  [self.server get:@"/deviceSS" withBlock:^(RouteRequest *request, RouteResponse *response) {
    [response respondWithData: [self screenshot]];
  }];

  [self registerRouteHandlers:@[FBUnknownCommands.class]];
}

@end
