#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface RootListController : PSListController
@end

@implementation RootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] retain];
    }
    return _specifiers;
}

@end
