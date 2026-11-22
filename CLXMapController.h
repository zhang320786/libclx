#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@interface CLXMapController : UIViewController
@property (nonatomic, copy) void (^onLocationPicked)(CLLocationCoordinate2D coord, NSString *name);
@end
