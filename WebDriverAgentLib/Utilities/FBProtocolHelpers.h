/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Inserts element uuid into the response dictionary

 @param dst The target dictionary. It is NOT mutated
 @param element Either element identifier or element object itself
 @returns The changed dictionary
 */
NSDictionary *FBInsertElement(NSDictionary *dst, id element);

/**
 Extracts element uuid from dictionary

 @param src The source dictionary
 @returns The resulting element uuid or nil if no element keys are found
 */
id _Nullable FBExtractElement(NSDictionary *src);

NS_ASSUME_NONNULL_END
