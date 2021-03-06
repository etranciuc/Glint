//
// GlintAppDelegate.m
// Glint
//
// Created by Jakob Borg on 6/26/09.
// Copyright Jakob Borg 2009. All rights reserved.
//

#import "FilesViewController.h"
#import "GlintAppDelegate.h"
#import "MainScreenViewController.h"

@interface GlintAppDelegate ()
- (void)loadRaceFile:(NSString*)raceAgainstFile;
- (void)updateDefaultSettings;
- (NSDictionary*)loadDefaultSettings;
- (void)resumeRecordingToFile;
- (void)resumeRacing;
@end

@implementation GlintAppDelegate

@synthesize window;
@synthesize mainScreenViewController;
@synthesize sendFilesViewController;
@synthesize navController;
@synthesize queue;
@synthesize reachManager;

- (void)dealloc
{
        [window release];
        [mainScreenViewController release];
        [sendFilesViewController release];
        [super dealloc];
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
        self.queue = [[NSOperationQueue alloc] init];

        [self updateDefaultSettings];

        [window addSubview:mainScreenViewController.view];
        [window addSubview:navController.view];
        [window bringSubviewToFront:mainScreenViewController.view];
        [window makeKeyAndVisible];

        [self resumeRecordingToFile];
        [self resumeRacing];

        reachManager = [[Reachability reachabilityForInternetConnection] retain];
        [reachManager startNotifer];

        [[UIApplication sharedApplication] setIdleTimerDisabled:YES];

        [self enableProximitySensor];

        return YES;
}

- (GPSManager*)gpsManager
{
        if (gpsManager == nil)
                // Start GPS manager
                gpsManager = [[GPSManager alloc] init];
        return gpsManager;
}

- (void)applicationWillTerminate:(UIApplication*)application
{
        [gpsManager disableGPS];
        [self disableProximitySensor];
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
        [mainScreenViewController stopTimers];
        [self disableProximitySensor];
        debug_NSLog(@"Entering background");
        if (![gpsManager isRecording]) {
                debug_NSLog(@"Entering background - disabled GPS");
                [gpsManager disableGPS];
        }
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
        debug_NSLog(@"Entering foreground");
        [self enableProximitySensor];
        [gpsManager enableGPS];
        [mainScreenViewController startTimers];
}

- (IBAction)switchToSendFilesView:(id)sender
{
        [self disableProximitySensor];
        [sendFilesViewController refresh];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleDefault animated:YES];
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:1.2];
        [UIView setAnimationRepeatAutoreverses:NO];
        [UIView setAnimationTransition:UIViewAnimationTransitionCurlUp forView:window cache:YES];
        [window bringSubviewToFront:navController.view];
        [UIView commitAnimations];
}

- (IBAction)switchToGPSView:(id)sender
{
        [self enableProximitySensor];
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationDuration:1.2];
        [UIView setAnimationRepeatAutoreverses:NO];
        [UIView setAnimationTransition:UIViewAnimationTransitionCurlDown forView:window cache:YES];
        [window bringSubviewToFront:mainScreenViewController.view];
        [UIView commitAnimations];
        [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque animated:YES];
}

- (void)setRaceAgainstLocations:(NSArray*)locations
{
        [[gpsManager math] setRaceLocations:locations];
}

// Global formatting functions

- (NSString*)formatTimestamp:(float)seconds maxTime:(float)max allowNegatives:(bool)allowNegatives
{
        bool negative = NO;
        if (isnan(seconds) || seconds > max || (!allowNegatives && seconds < 0))
                return [NSString stringWithFormat:@"?"];
        else {
                if (seconds < 0) {
                        seconds = -seconds;
                        negative = YES;
                }
                int isec = (int) seconds;
                int hour = (int) (isec / 3600);
                int min = (int) ((isec % 3600) / 60);
                int sec = (int) (isec % 60);
                if (hour == 0) {
                        if (allowNegatives && !negative)
                                return [NSString stringWithFormat:@"+%02d:%02d", min, sec];
                        else if (negative)
                                return [NSString stringWithFormat:@"-%02d:%02d", min, sec];
                        else
                                return [NSString stringWithFormat:@"%02d:%02d", min, sec];
                } else {
                        if (allowNegatives && !negative)
                                return [NSString stringWithFormat:@"+%02d:%02d:%02d", hour, min, sec];
                        else if (negative)
                                return [NSString stringWithFormat:@"-%02d:%02d:%02d", hour, min, sec];
                        else
                                return [NSString stringWithFormat:@"%02d:%02d:%02d", hour, min, sec];
                }
        }
}

- (NSString*)formatDMS:(float)latLong
{
        int deg = (int) latLong;
        int min = (int) ((latLong - deg) * 60);
        float sec = (float) ((latLong - deg - min / 60.0) * 3600.0);
        return [NSString stringWithFormat:@"%02d° %02d' %02.02f\"", deg, min, sec];
}

- (NSString*)formatLat:(float)lat
{
        NSString *sign = lat >= 0 ? @"N" : @"S";
        lat = fabs(lat);
        return [NSString stringWithFormat:@"%@ %@", [self formatDMS:lat], sign];
}

- (NSString*)formatLon:(float)lon
{
        NSString *sign = lon >= 0 ? @"E" : @"W";
        lon = fabs(lon);
        return [NSString stringWithFormat:@"%@ %@", [self formatDMS:lon], sign];
}

- (NSDictionary*)currentUnitset
{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"unitsets" ofType:@"plist"];
        NSArray *unitSets = [NSArray arrayWithContentsOfFile:path];
        NSDictionary *units = [unitSets objectAtIndex:USERPREF_UNITSET];
        return units;
}

- (NSString*)formatDistance:(float)distance
{
        static float distFactor = 0;
        static NSString *distFormat = nil;

        if (distFormat == nil) {
                NSDictionary *units = [self currentUnitset];
                distFactor = [[units objectForKey:@"distFactor"] floatValue];
                distFormat = [units objectForKey:@"distFormat"];
                [distFormat retain];
        }

        return [NSString stringWithFormat:distFormat, distance * distFactor];
}

- (NSString*)formatShortDistance:(float)distance
{
        static float shortDistFactor = 0;
        static NSString *shortDistFormat = nil;

        if (shortDistFormat == nil) {
                NSDictionary *units = [self currentUnitset];
                shortDistFactor = [[units objectForKey:@"shortDistFactor"] floatValue];
                shortDistFormat = [units objectForKey:@"shortDistFormat"];
                [shortDistFormat retain];
        }

        return [NSString stringWithFormat:shortDistFormat, distance * shortDistFactor];
}

- (NSString*)formatSpeed:(float)speed
{
        static float speedFactor = 0;
        static NSString *speedFormat = nil;

        if (speedFormat == nil) {
                NSDictionary *units = [self currentUnitset];
                speedFactor = [[units objectForKey:@"speedFactor"] floatValue];
                speedFormat = [units objectForKey:@"speedFormat"];
                [speedFormat retain];
        }

        return [NSString stringWithFormat:speedFormat, speed * speedFactor];
}

- (void)enableProximitySensor
{
        if (USERPREF_ENABLE_PROXIMITY) {
                [[UIDevice currentDevice] setProximityMonitoringEnabled:YES];
                debug_NSLog(@"Enabling proximity sensor");
        }
}

- (void)disableProximitySensor
{
        if (USERPREF_ENABLE_PROXIMITY) {
                [[UIDevice currentDevice] setProximityMonitoringEnabled:NO];
                debug_NSLog(@"Disabling proximity sensor");
        }
}

// Private

- (void)loadRaceFile:(NSString*)raceAgainstFile
{
        GPXReader *reader = [[GPXReader alloc] initWithFilename:raceAgainstFile];
        [[gpsManager math] setRaceLocations:[reader locations]];
        [reader release];
}

- (void)updateDefaultSettings
{
        // Register defaults
        NSDictionary *defaults = [self loadDefaultSettings];
        [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];
        [defaults release];

        NSString *currentVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        // Check the preferences are up to speed, and load new defaults if not.
        NSString *defaultsVersion = [[NSUserDefaults standardUserDefaults] stringForKey:@"current_version"];
        if (defaultsVersion == nil || [currentVersion compare:defaultsVersion] != NSOrderedSame) {
                // Remind user about the need for GPS signal after upgrade.
                [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"have_shown_gps_instructions"];
                [[NSUserDefaults standardUserDefaults] setObject:currentVersion forKey:@"current_version"];
                [[NSUserDefaults standardUserDefaults] synchronize];
        }
}

- (NSDictionary*)loadDefaultSettings
{
        NSString *pathStr = [[NSBundle mainBundle] bundlePath];
        NSString *settingsBundlePath = [pathStr stringByAppendingPathComponent:@"Settings.bundle"];
        NSString *finalPath = [settingsBundlePath stringByAppendingPathComponent:@"Root.plist"];

        NSDictionary *settingsDict = [NSDictionary dictionaryWithContentsOfFile:finalPath];
        NSArray *prefSpecifierArray = [settingsDict objectForKey:@"PreferenceSpecifiers"];

        NSMutableDictionary *defaults = [[NSMutableDictionary alloc] init];
        for (NSDictionary*prefItem in prefSpecifierArray) {
                NSString *keyValueStr = [prefItem objectForKey:@"Key"];
                id defaultValue = [prefItem objectForKey:@"DefaultValue"];
                if (keyValueStr && defaultValue) {
                        [defaults setObject:defaultValue forKey:keyValueStr];
                        debug_NSLog(@"Setting preference: %@=%@", keyValueStr, [defaultValue description]);
                }
        }
        return defaults;
}

- (void)resumeRecordingToFile
{
        NSString *recordingFile;
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"restart_recording"] &&
            (recordingFile = [[NSUserDefaults standardUserDefaults] stringForKey:@"recording_filename"]))
                [self.queue addOperation:[[[NSInvocationOperation alloc] initWithTarget:mainScreenViewController selector:@selector(resumeRecordingOnFile:) object:recordingFile] autorelease]];
}

- (void)resumeRacing
{
        NSString *raceAgainstFile;
        if ((raceAgainstFile = [[NSUserDefaults standardUserDefaults] stringForKey:@"raceAgainstFile"]))
                [self.queue addOperation:[[[NSInvocationOperation alloc] initWithTarget:self selector:@selector(loadRaceFile:) object:raceAgainstFile] autorelease]];
}

@end
