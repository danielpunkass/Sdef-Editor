//
//  AeteImporter.m
//  Sdef Editor
//
//  Created by Grayfox on 30/01/05.
//  Copyright 2005 Shadow Lab. All rights reserved.
//

#import "AeteImporter.h"
#import "ShadowMacros.h"
#import "SKFunctions.h"
#import "SKExtensions.h"

#import "SdefSuite.h"
#import "SdefClass.h"
#import "SdefEnumeration.h"
#import "SdefClassManager.h"

#import "AeteObject.h"
#import "ShadowAEUtils.h"
#include <Carbon/Carbon.h>

struct AeteHeader {
  UInt8 majorVersion;
  UInt8 minorVersion;
  UInt16 lang;
  UInt16 script;
  UInt16 suiteCount;
};
typedef struct AeteHeader AeteHeader;

@implementation AeteImporter

OSStatus _GetTerminologyFromAppleEvent(AppleEvent *theEvent, NSMutableArray *terminolgies) {
  SInt32 idx;
  long count = 0;
  AEDescList aetes = {typeNull, nil};
  
  OSStatus err = ShadowAEAddMagnitude(theEvent);
  require_noerr(err, bail);
  
  err = ShadowAEAddSubject(theEvent);
  require_noerr(err, bail);
  
  err = ShadowAEAddSInt32(theEvent, keyDirectObject, 0);
  require_noerr(err, bail);
  
  err = ShadowAESendEventReturnAEDescList(theEvent, &aetes);
  require_noerr(err, bail);

  err = AECountItems(&aetes, &count);
  require_noerr(err, bail);

  for (idx = 1; idx <= count; idx++) {
    CFDataRef data = NULL;
    ShadowAEGetNthCFDataFromDescList(&aetes, idx, typeAETE, &data);
    if (data) {
      [terminolgies addObject:(id)data];
      CFRelease(data);
    }
  }

bail:
  ShadowAEDisposeDesc(&aetes);
  return err;
}

- (id)_initWithTarget:(AEDesc *)target {
  if (self = [super init]) {
    AppleEvent theEvent = {typeNull, nil};
    sd_aetes = [[NSMutableArray alloc] init];
    OSStatus err = ShadowAECreateEventWithTarget(target, kASAppleScriptSuite, kGetAEUT, &theEvent);
    require_noerr(err, bail);
    
    err = _GetTerminologyFromAppleEvent(&theEvent, sd_aetes);
    ShadowAEDisposeDesc(&theEvent);
    
    err = ShadowAECreateEventWithTarget(target, kASAppleScriptSuite, kGetAETE, &theEvent);
    require_noerr(err, bail);
    
    err = _GetTerminologyFromAppleEvent(&theEvent, sd_aetes);
    ShadowAEDisposeDesc(&theEvent);
    
    require(sd_aetes && [sd_aetes count], bail);
  }
  return self;
/* On Error */
bail:
  [sd_aetes release];
  sd_aetes = nil;
  [self release];
  self = nil;
  return self;
}

- (id)initWithApplicationSignature:(OSType)signature {
  AEDesc target;
  OSStatus err = ShadowAECreateTargetWithSignature(signature, NO, &target);
  if (noErr == err) {
    self = [self _initWithTarget:&target];
  } else {
    [self release];
    self = nil;
  }
  ShadowAEDisposeDesc(&target);
  return self;
}

- (id)initWithApplicationBundleIdentifier:(NSString *)identifier {
  AEDesc target;
  OSStatus err = ShadowAECreateTargetWithBundleID((CFStringRef)identifier, NO, &target);
  if (noErr == err) {
    self = [self _initWithTarget:&target];
  } else {
    [self release];
    self = nil;
  }
  ShadowAEDisposeDesc(&target);
  return self;
}

- (id)initWithFSRef:(FSRef *)aRef {
  if (self = [super init]) {
    short fileRef;
    OSStatus err = FSOpenResourceFile(aRef, 0, NULL, fsRdPerm, &fileRef);
    if (mapReadErr == err) {
      HFSUniStr255 rsrcName;
      if (noErr == FSGetResourceForkName(&rsrcName)) {
        err = FSOpenResourceFile(aRef, rsrcName.length, rsrcName.unicode, fsRdPerm, &fileRef);
      }
    }
    if(noErr == err) {
      short count;
      unsigned idx;
      /* Standard Infos */
      count = Count1Resources(kAEUserTerminology);
      sd_aetes = [[NSMutableArray alloc] initWithCapacity:count];
      for (idx = 1; idx <= count; idx++) {
        Handle aeteH = Get1IndResource(kAEUserTerminology, idx);
        id aete = [[NSData alloc] initWithHandle:aeteH];
        if (aete) {
          [sd_aetes addObject:aete];
          [aete release];
        }
      }
      /* Extensions */
      count = Count1Resources(kAETerminologyExtension);
      sd_aetes = [[NSMutableArray alloc] initWithCapacity:count];
      for (idx = 1; idx <= count; idx++) {
        Handle aeteH = Get1IndResource(kAETerminologyExtension, idx);
        id aete = [[NSData alloc] initWithHandle:aeteH];
        if (aete) {
          [sd_aetes addObject:aete];
          [aete release];
        }
      }
      CloseResFile(fileRef);
    }
    if (!sd_aetes) {
      [self release];
      self = nil;
    }
  }
  return self;
}

- (id)initWithContentsOfFile:(NSString *)aFile {
  FSRef aRef;
  if (![aFile getFSRef:&aRef]) {
    [self release];
    self = nil;
  } else {
    self = [self initWithFSRef:&aRef];
  }
  return self;
}

- (void)dealloc {
  [sd_aetes release];
  [super dealloc];
}

#pragma mark -
#pragma mark Parsing

- (BOOL)import {
  id aetes = [sd_aetes objectEnumerator];
  NSData *aete;
  while (aete = [aetes nextObject]) {
    @try {
      BytePtr bytes = (BytePtr)[aete bytes];
      ByteOffset offset = 0;
      AeteHeader *header = (AeteHeader *)bytes;
      bytes += sizeof(AeteHeader);
      offset += sizeof(AeteHeader);
      unsigned idx = 0;
      for (idx=0; idx<header->suiteCount; idx++) {
        SdefSuite *suite = [[SdefSuite allocWithZone:[self zone]] init];
        bytes += [suite parseData:bytes];
        [suites addObject:suite];
        [suite release];
      }
    } @catch (id exception) {
      SKLogException(exception);
      [suites removeAllObjects];
      return NO;
    }
  }
  return YES;
}

#pragma mark Post Processor
- (BOOL)resolveObjectType:(SdefObject *)obj {
  NSString *type = [obj valueForKey:@"type"];
  BOOL isList = NO;
  if ([type hasPrefix:@"list of"]) {
    isList = YES;
    type = [type substringFromIndex:8];
  }
  NSString *typename = [manager sdefTypeForAeteType:type];
  if (!typename) {
    typename = [[manager sdefTypeWithCode:type inSuite:nil] name];
  }
  if (typename) {
    if (isList) typename = [@"list of " stringByAppendingString:typename];
    [obj setValue:typename forKey:@"type"];
    return YES;
  }
  return NO;
}

- (void)postProcessClass:(SdefClass *)aClass {
  if ([[aClass properties] childCount]) {
    SdefProperty *info = [[aClass properties] firstChild];
    if (SKHFSTypeCodeFromFileType([info codeStr]) == pInherits) {
      id superclass = [manager sdefClassWithCode:[info type] inSuite:nil];
      if (superclass) {
        [aClass setInherits:[superclass name]];
      } else {
        [self addWarning:[NSString stringWithFormat:@"Unable to find superclass: %@", [info type]]
                forValue:[aClass name]];
      }
      [info remove];
    } else if (SKHFSTypeCodeFromFileType([info codeStr]) == kAESpecialClassProperties) {
      if ([[info name] isEqualToString:@"<Plural>"]) {
        unsigned idx = [aClass index];
        [[[aClass parent] childAtIndex:idx-1] setPlural:[aClass name]];
        [aClass remove];
      } else {
        [self addWarning:@"Unable to import Special Properties" forValue:[aClass name]];
      }      
    }
  }
  [super postProcessClass:aClass];
}

@end
