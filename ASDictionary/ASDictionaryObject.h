//
//  ASDictionaryObject.h
//  Sdef Editor
//
//  Created by Grayfox on 27/02/05.
//  Copyright 2005 Shadow Lab. All rights reserved.
//

#import "SdefBase.h"
#import "ShadowMacros.h"

@interface SdefObject (ASDictionary)

- (NSDictionary *)asdictionary;
- (NSDictionary *)asdictionaryString;
- (NSString *)asDictionaryTypeForType:(NSString *)type isList:(BOOL *)list;

@end
