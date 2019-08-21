/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBExceptionHandler.h"

#import <RoutingHTTPServer/RouteResponse.h>

#import "FBAlert.h"
#import "FBResponsePayload.h"
#import "FBSession.h"
#import "XCUIElement+FBClassChain.h"
#import "FBXPath.h"


NSString *const FBInvalidArgumentException = @"FBInvalidArgumentException";
NSString *const FBSessionDoesNotExistException = @"FBSessionDoesNotExistException";
NSString *const FBApplicationDeadlockDetectedException = @"FBApplicationDeadlockDetectedException";
NSString *const FBElementAttributeUnknownException = @"FBElementAttributeUnknownException";
NSString *const FBElementNotVisibleException = @"FBElementNotVisibleException";

@implementation FBExceptionHandler

- (void)handleException:(NSException *)exception forResponse:(RouteResponse *)response
{
  id<FBResponsePayload> payload;
  NSString *traceback = [NSString stringWithFormat:@"%@", exception.callStackSymbols];
  if ([exception.name isEqualToString:FBSessionDoesNotExistException]) {
    payload = FBResponseWithStatus([FBCommandStatus noSuchDriverErrorWithMessage:exception.reason
                                                                       traceback:traceback]);
  } else if ([exception.name isEqualToString:FBInvalidArgumentException]
             || [exception.name isEqualToString:FBElementAttributeUnknownException]) {
    payload = FBResponseWithStatus([FBCommandStatus invalidArgumentErrorWithMessage:exception.reason
                                                                          traceback:traceback]);
  } else if ([exception.name isEqualToString:FBAlertObstructingElementException]) {
    payload = FBResponseWithStatus([FBCommandStatus unexpectedAlertOpenErrorWithMessage:nil
                                                                              traceback:traceback]);
  } else if ([exception.name isEqualToString:FBApplicationCrashedException]
             || [exception.name isEqualToString:FBApplicationDeadlockDetectedException]) {
    payload = FBResponseWithStatus([FBCommandStatus invalidElementStateErrorWithMessage:exception.reason
                                                                              traceback:traceback]);
  } else if ([exception.name isEqualToString:FBInvalidXPathException]
             || [exception.name isEqualToString:FBClassChainQueryParseException]) {
    payload = FBResponseWithStatus([FBCommandStatus invalidSelectorErrorWithMessage:exception.reason
                                                                          traceback:traceback]);
  } else if ([exception.name isEqualToString:FBElementNotVisibleException]) {
    payload = FBResponseWithStatus([FBCommandStatus elementNotVisibleErrorWithMessage:exception.reason
                                                                            traceback:traceback]);
  } else {
    payload = FBResponseWithStatus([FBCommandStatus unknownErrorWithMessage:exception.reason
                                                                  traceback:traceback]);
  }
  [payload dispatchWithResponse:response];
}

@end
