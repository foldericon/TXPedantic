/*
 ===============================================================================
 Copyright (c) 2014, Tobias Pollmann (foldericon)
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * Neither the name of the <organization> nor the
 names of its contributors may be used to endorse or promote products
 derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 ===============================================================================
*/


#import "TXPedantic.h"
#import <AutoHyperlinks/AutoHyperlinks.h>

@implementation TXPedantic

#pragma mark -
#pragma mark Plugin API

BOOL pedanticenabled = NO;
BOOL pedanticmyself = NO;

- (void)pluginLoadedIntoMemory:(IRCWorld *)world
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self preferencesPath]]) {
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              @"no", @"PedanticEnabled",
                              @"no", @"PedanticForMyself",
                              nil];
        [self setPreferences:dict];
    } else {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:self.preferencesPath];
        if([[dict objectForKey:@"PedanticEnabled"] boolValue] == YES) {
            pedanticenabled = YES;
        }
    }
}


- (NSArray *)subscribedUserInputCommands
{
    return @[@"pedantic"];
}


- (void)userInputCommandInvokedOnClient:(IRCClient *)client
                          commandString:(NSString *)commandString
                          messageString:(NSString *)messageString
{
    if([messageString isEqualToString:@"enable"]) {
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithDictionary:[NSDictionary dictionaryWithContentsOfFile:self.preferencesPath]];
        [prefs setObject:@"yes" forKey:@"PedanticEnabled"];
        [self setPreferences:prefs];
        pedanticenabled = YES;
        [client printDebugInformation:@"Pedantic enabled."];
    } else if([messageString isEqualToString:@"disable"]) {
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithDictionary:[NSDictionary dictionaryWithContentsOfFile:self.preferencesPath]];
        [prefs setObject:@"no" forKey:@"PedanticEnabled"];
        [self setPreferences:prefs];
        pedanticenabled = NO;
        [client printDebugInformation:@"Pedantic disabled."];
    } else if([messageString isEqualToString:@"enableformyself"]) {
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithDictionary:[NSDictionary dictionaryWithContentsOfFile:self.preferencesPath]];
        [prefs setObject:@"yes" forKey:@"PedanticForMyself"];
        [self setPreferences:prefs];
        pedanticmyself = YES;
        [client printDebugInformation:@"Correcting user input enabled."];
    } else if([messageString isEqualToString:@"disableformyself"]) {
        NSMutableDictionary *prefs = [[NSMutableDictionary alloc] initWithDictionary:[NSDictionary dictionaryWithContentsOfFile:self.preferencesPath]];
        [prefs setObject:@"no" forKey:@"PedanticForMyself"];
        [self setPreferences:prefs];
        pedanticmyself = NO;
        [client printDebugInformation:@"Correcting user input disabled."];
    }
    
}

- (IRCMessage *)interceptServerInput:(IRCMessage *)input for:(IRCClient *)client
{
    if([input.command isNotEqualTo:@"PRIVMSG"])
        return input;
    
    if(!pedanticenabled)
        return input;
    
    NSString *message = [self correctString:input.params[1] forChannel:[client findChannel:input.params[0]]];
    [input setParams:[NSArray arrayWithObjects:input.params[0], message, nil]];
    return input;
}


- (id)interceptUserInput:(id)input command:(NSString *)command
{
    if([command isNotEqualTo:@"PRIVMSG"])
        return input;
    
    if(!pedanticmyself)
        return input;
    
    NSAttributedString *attributedString = input;
    NSDictionary *attributes = attributedString.attributes;
    NSString *message = [attributedString string];

    NSString *output = [self correctString:message forChannel:mainWindow().selectedChannel];

    return [[NSAttributedString alloc] initWithString:output attributes:attributes];
}


#pragma mark -
#pragma mark Helper Methods

- (NSString *)correctString:(NSString *)string forChannel:(IRCChannel *)channel
{
    
    NSString *message = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *links = [[[AHHyperlinkScanner alloc] init] matchesForString:message];
    
    NSMutableArray *words = [[NSMutableArray alloc] init];
    NSMutableArray *nicks = [[NSMutableArray alloc] init];
    for (IRCUser* user in [channel sortedByChannelRankMemberList]) {
        [nicks addObject:user.nickname];
    }
    
    BOOL shouldBeLowerCased = [self shouldBeLowerCased:message withLinks:links andNicks:nicks];
    
    NSArray *aryMsg = [message split:@" "];
    
    int count = 0;

    for (int i=0; i<aryMsg.count; i++) {

        NSString *msg = aryMsg[i];
        
        BOOL isLink = NO;
        // Check if current word is a hyperlink
        for (NSArray *ary in links) {
            NSRange range = NSRangeFromString(ary[0]);
            if(count == (int)range.location) {
                isLink = YES;
                [words addObject:msg];
                break;
            }
        }
        count += msg.length+1;
        if(isLink)
            continue;
        
        // Check if current word is a nickname
        if([nicks containsObjectIgnoringCase:msg]) {
            [words addObject:[channel findMember:msg.lowercaseString].nickname];
        } else  {
            msg = [self correctWord:msg];
            if(shouldBeLowerCased)
                msg = [msg lowercaseString];
            
            // Check if first word
            if(aryMsg.count > 2 && i == 0) {
                msg = [[[[msg substringFromIndex:0] substringToIndex:1] uppercaseString] stringByAppendingString:[msg substringFromIndex:1]];
                
            // Check if last word
            } else if(aryMsg.count > 2 && i == aryMsg.count-1) {
                if([[msg stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]] length] > 1) {
                    if([msg hasSuffix:@"!"] == NO && [msg hasSuffix:@"?"] == NO && [msg hasSuffix:@";"] == NO && [msg hasSuffix:@"."] == NO) {
                        msg = [msg stringByAppendingString:@"."];
                    } else {
                        if ([[NSString stringWithFormat:@"%c", [msg characterAtIndex:msg.length-2]] isEqualToString:@" "]) {
                            NSString *character = [msg substringFromIndex:msg.length-1];
                            msg = [[msg substringToIndex:msg.length-1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                            msg = [msg stringByAppendingString:character];
                        }
                    }
                }
                msg = [msg stringByReplacingOccurrencesOfString:@"??" withString:@"?"];
                msg = [msg stringByReplacingOccurrencesOfString:@"!!" withString:@"!"];
            }
            [words addObject:msg];
        }
    }
    
    message = [words componentsJoinedByString:@" "];
    return message;
}


- (NSArray *)wordList {
    return @[
                @[@"im", @"I'm"],
                @[@"i", @"I"],
                @[@"thats", @"that's"],
                @[@"theres", @"there's"],
                @[@"cant", @"can't"],
                @[@"dont", @"don't"],
                @[@"doesnt", @"doesn't"],
                @[@"aint", @"ain't"],
                @[@"isnt", @"isn't"],
                @[@"hasnt", @"hasn't"],
                @[@"havent", @"haven't"],
                @[@"hadnt", @"hadn't"],
                @[@"didnt", @"didn't"],
                @[@"youre", @"you're"],
                @[@"theyre", @"they're"],
                @[@"arent", @"aren't"],
                @[@"wasnt", @"wasn't"],
                @[@"werent", @"weren't"],
                @[@"wont", @"won't"],
                @[@"shouldnt", @"shouldn't"],
                @[@"wouldnt", @"wouldn't"],
                @[@"couldnt", @"couldn't"],
                @[@"shouldve", @"should've"],
                @[@"wouldve", @"would've"],
                @[@"couldve", @"could've"],
                @[@"shant", @"shan't"]
            ];
}

- (NSString *)correctWord:(NSString *)word
{
    for (NSArray *pair in [self wordList]) {
        if([[word stringByTrimmingCharactersInSet:[NSCharacterSet punctuationCharacterSet]] isEqualIgnoringCase:pair[0]]) {
            return [word.lowercaseString stringByReplacingOccurrencesOfString:pair[0] withString:pair[1]];
        }
    }
    return word;
}

- (NSString *)preferencesPath
{
    return [[NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), [[NSBundle bundleForClass:[self class]] bundleIdentifier]] stringByExpandingTildeInPath];
}

- (void)setPreferences:(NSDictionary *)dictionary
{
    NSData *serializedData;
    NSString *error;
    serializedData = [NSPropertyListSerialization dataFromPropertyList:dictionary
                                                                format:NSPropertyListBinaryFormat_v1_0
                                                      errorDescription:&error];
    if (serializedData)
        [serializedData writeToFile:[self preferencesPath] atomically:YES];
    else
        NSLog(@"Error: %@", error);
}

- (BOOL)shouldBeLowerCased:(NSString *)string withLinks:(NSArray *)links andNicks:(NSArray *)nicks
{
    if(string.length < 6)
        return NO;
    
    // Remove Links
    NSString *originalString = string;
    for(NSArray *ary in links)
        string = [string stringByReplacingOccurrencesOfString:[originalString substringWithRange:NSRangeFromString(ary[0])] withString:@""];
    
    // Remove nicks
    for (NSString *word in [string split:@" "]) {
        if([nicks containsObjectIgnoringCase:word])
            string = [string stringByReplacingOccurrencesOfString:word withString:@""];
    }
    
    // Is more than 85% uppercase?
    NSUInteger count = [[[string componentsSeparatedByCharactersInSet:[[NSCharacterSet uppercaseLetterCharacterSet] invertedSet]] componentsJoinedByString:@""] length];
    if(count > string.length*0.85) {
        return YES;
    }
    return NO;
}

@end
