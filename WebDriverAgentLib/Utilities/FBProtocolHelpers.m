/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProtocolHelpers.h"

static NSString *const W3C_ELEMENT_KEY = @"element-6066-11e4-a52e-4f735466cecf";
static NSString *const JSONWP_ELEMENT_KEY = @"ELEMENT";

NSDictionary *FBInsertElement(NSDictionary *dst, id element)
{
  NSMutableDictionary *result = dst.mutableCopy;
  result[W3C_ELEMENT_KEY] = element;
  result[JSONWP_ELEMENT_KEY] = element;
  return result.copy;
}

id FBExtractElement(NSDictionary *src)
{
  for (NSString* key in src) {
    if ([key.lowercaseString isEqualToString:W3C_ELEMENT_KEY.lowercaseString]
        || [key.lowercaseString isEqualToString:JSONWP_ELEMENT_KEY.lowercaseString]) {
      return src[key];
    }
  }
  return nil;
}
