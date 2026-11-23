#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <ServiceManagement/ServiceManagement.h>

@interface Follow : NSObject <NSApplicationDelegate, NSMenuDelegate>
@end

@implementation Follow {
    NSStatusItem *_item;
    NSMenu *_menu;
    NSMutableSet<NSNumber *> *_keyboards;
    NSString *_lastAction;
    NSTask *_task;
    IONotificationPortRef _port;
    io_iterator_t _arrivals, _departures;
    BOOL _ready;
}
- (NSInteger)slot { return [NSUserDefaults.standardUserDefaults integerForKey:@"localSlot"]; }

- (void)sendMouse {
    NSInteger slot = self.slot;
    if ((slot != 1 && slot != 2) || _task.running) return;
    NSString *target = slot == 1 ? @"2" : @"1";
    NSTask *task = [NSTask new];
    task.executableURL = [NSBundle.mainBundle URLForAuxiliaryExecutable:@"mxswitch"];
    task.arguments = @[target, @"--name", @"MX Master 3", @"--config", @"/dev/null"];
    task.standardOutput = NSFileHandle.fileHandleWithNullDevice;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    __weak Follow *weakSelf = self;
    task.terminationHandler = ^(NSTask *ended) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Follow *owner = weakSelf;
            if (!owner || owner->_task != ended) return;
            owner->_task = nil;
            owner->_lastAction = ended.terminationStatus == 0 ?
                [@"Sent mouse to slot " stringByAppendingString:target] :
                @"Mouse unavailable · check Input Monitoring";
            [owner refresh];
        });
    };
    NSError *error = nil;
    _task = task;
    if (![task launchAndReturnError:&error]) {
        _task = nil;
        _lastAction = error.localizedDescription;
    }
}

- (void)drain:(io_iterator_t)iterator {
    BOOL wasConnected = _keyboards.count > 0;
    io_service_t device;
    while ((device = IOIteratorNext(iterator))) {
        uint64_t identifier;
        if (IORegistryEntryGetRegistryEntryID(device, &identifier) == KERN_SUCCESS) {
            if (iterator == _departures) {
                [_keyboards removeObject:@(identifier)];
            } else {
                NSString *name = CFBridgingRelease(IORegistryEntryCreateCFProperty(device, CFSTR("Product"), NULL, 0));
                NSString *transport = CFBridgingRelease(IORegistryEntryCreateCFProperty(device, CFSTR("Transport"), NULL, 0));
                if ([name hasPrefix:@"NuPhy Air75 V2"] && [transport hasPrefix:@"Bluetooth"])
                    [_keyboards addObject:@(identifier)];
            }
        }
        IOObjectRelease(device);
    }
    if (_ready && wasConnected && !_keyboards.count) [self sendMouse];
    if (_ready) [self refresh];
}
static void changed(void *context, io_iterator_t iterator) {
    [(__bridge Follow *)context drain:iterator];
}

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _keyboards = [NSMutableSet set];
    _item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    _item.button.image = [NSImage imageWithSystemSymbolName:@"keyboard" accessibilityDescription:@"Keyboard Mouse Switcher"];
    _item.button.toolTip = @"Keyboard Mouse Switcher";
    _menu = [NSMenu new];
    _menu.autoenablesItems = NO;
    _menu.delegate = self;
    _item.menu = _menu;
    _port = IONotificationPortCreate(kIOMainPortDefault);
    if (_port) {
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(_port), kCFRunLoopCommonModes);
        if (IOServiceAddMatchingNotification(_port, kIOFirstMatchNotification, IOServiceMatching("IOHIDDevice"), changed, (__bridge void *)self, &_arrivals) == KERN_SUCCESS &&
            IOServiceAddMatchingNotification(_port, kIOTerminatedNotification, IOServiceMatching("IOHIDDevice"), changed, (__bridge void *)self, &_departures) == KERN_SUCCESS) {
            [self drain:_arrivals];
            [self drain:_departures];
            _ready = YES;
        }
    }
    [self refresh];
}

- (void)choose:(NSMenuItem *)sender {
    [NSUserDefaults.standardUserDefaults setInteger:sender.tag forKey:@"localSlot"];
    _lastAction = nil;
    [self refresh];
}
- (void)login:(id)sender {
    SMAppService *service = SMAppService.mainAppService;
    NSError *error = nil;
    if (service.status == SMAppServiceStatusRequiresApproval) [SMAppService openSystemSettingsLoginItems];
    else if (service.status == SMAppServiceStatusEnabled) [service unregisterAndReturnError:&error];
    else [service registerAndReturnError:&error];
    if (error) _lastAction = error.localizedDescription;
    [self refresh];
}
- (void)privacy:(id)sender {
    [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"]];
}
/* The bundled mxswitch needs Input Monitoring to talk to the mouse, and macOS
 * attributes its access to this app. Asking here shows the system prompt and
 * adds the app to the Input Monitoring list.
 *
 * macOS never prompts again once access is "denied" - and a rebuilt (re-signed)
 * copy of the app inherits a stale entry that reads as denied even while the
 * old toggle still looks on. So clear this app's own entry first, then ask. */
- (void)enableInputMonitoring:(id)sender {
    if (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeDenied) {
        NSTask *reset = [NSTask new];
        reset.executableURL = [NSURL fileURLWithPath:@"/usr/bin/tccutil"];
        reset.arguments = @[@"reset", @"ListenEvent", NSBundle.mainBundle.bundleIdentifier];
        reset.standardOutput = NSFileHandle.fileHandleWithNullDevice;
        reset.standardError = NSFileHandle.fileHandleWithNullDevice;
        if ([reset launchAndReturnError:nil]) [reset waitUntilExit];
    }
    if (IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)) {
        _lastAction = @"Input Monitoring enabled";
    } else {
        /* Prompting adds the app to the list switched off; the user turns it on. */
        _lastAction = @"Turn on Keyboard Mouse Switcher in Input Monitoring";
        [self privacy:sender];
    }
    [self refresh];
}
- (void)menuNeedsUpdate:(NSMenu *)menu { [self refresh]; }
- (NSMenuItem *)row:(NSString *)title action:(SEL)action {
    NSMenuItem *item = [_menu addItemWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    item.enabled = action != NULL;
    return item;
}
- (void)refresh {
    [_menu removeAllItems];
    [self row:!_ready ? @"Keyboard watcher unavailable" :
        _keyboards.count ? @"NuPhy Air75 V2 connected" : @"Waiting for NuPhy Air75 V2" action:NULL];
    if (_lastAction.length) [self row:_lastAction action:NULL];
    [_menu addItem:NSMenuItem.separatorItem];
    [self row:@"This Mac is" action:NULL];
    for (NSInteger slot = 1; slot <= 2; slot++) {
        NSMenuItem *item = [self row:[NSString stringWithFormat:@"Slot %ld", (long)slot] action:@selector(choose:)];
        item.tag = slot;
        item.state = self.slot == slot ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [self row:self.slot == 1 ? @"Mouse follows to slot 2" : self.slot == 2 ? @"Mouse follows to slot 1" : @"Choose a slot to enable switching" action:NULL];
    [_menu addItem:NSMenuItem.separatorItem];
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    NSMenuItem *login = [self row:status == SMAppServiceStatusRequiresApproval ? @"Approve Open at Login…" : @"Open at Login" action:@selector(login:)];
    login.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted) {
        NSMenuItem *monitoring = [self row:@"Input Monitoring Enabled" action:@selector(privacy:)];
        monitoring.state = NSControlStateValueOn;
    } else {
        [self row:@"Enable Input Monitoring…" action:@selector(enableInputMonitoring:)];
    }
    [_menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [self row:@"Quit Keyboard Mouse Switcher" action:@selector(terminate:)];
    quit.target = NSApp;
    quit.keyEquivalent = @"q";
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        Follow *delegate = [Follow new];
        app.delegate = delegate;
        [app run];
        (void)delegate;
    }
    return 0;
}
