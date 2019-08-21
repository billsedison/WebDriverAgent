/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBUnknownCommands.h"

#import "FBRouteRequest.h"

@implementation FBUnknownCommands

#pragma mark - <FBCommandHandler>

+ (BOOL)shouldRegisterAutomatically
{
  return NO;
}

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/*"].withoutSession respondWithTarget:self action:@selector(unhandledHandler:)],
    [[FBRoute POST:@"/*"].withoutSession respondWithTarget:self action:@selector(unhandledHandler:)],
    [[FBRoute PUT:@"/*"].withoutSession respondWithTarget:self action:@selector(unhandledHandler:)],
    [[FBRoute DELETE:@"/*"].withoutSession respondWithTarget:self action:@selector(unhandledHandler:)],
    [[FBRoute OPTIONS:@"/*"].withoutSession respondWithTarget:self action:@selector(options:)]
  ];
}

+ (id<FBResponsePayload>)unhandledHandler:(FBRouteRequest *)request
{
  return
  FBResponseWithStatus(
    FBCommandStatusUnsupported,
    [NSString stringWithFormat:@"Unhandled endpoint: %@ with parameters %@", request.URL, request.parameters]
  );
}

+ (id<FBResponsePayload>)options:(FBRouteRequest *)request
{
  return FBResponseWithOK();
}


@end
