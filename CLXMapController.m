#import "CLXMapController.h"
#import "CLXStore.h"
#import "CLXShared.h"

@interface CLXMapController () <UISearchBarDelegate, MKMapViewDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchBar *searchBar;
@property (nonatomic, strong) UITableView *resultsTable;
@property (nonatomic, strong) NSArray<MKMapItem *> *searchResults;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UIImageView *pin;
@property (nonatomic, assign) CLLocationCoordinate2D currentCoord;   // GCJ-02（地图显示坐标）
@property (nonatomic, copy)   NSString *currentName;
@end

@implementation CLXMapController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择位置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = NO;
    [self.view addSubview:self.mapView];

    // 存储的是 WGS-84，地图显示需要 GCJ-02
    CLLocationCoordinate2D stored = [CLXStore target];
    if (CLXCoordinateValid(stored)) {
        self.currentCoord = CLXWGS84ToGCJ02(stored);
        self.currentName = [CLXStore targetName];
    } else {
        self.currentCoord = CLLocationCoordinate2DMake(39.9087, 116.3975);   // 天安门
        self.currentName = @"";
    }
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(self.currentCoord, 400, 400) animated:NO];

    self.pin = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 32, 32)];
    self.pin.image = [self pinImage];
    [self.view addSubview:self.pin];

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地点";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.searchBar];

    self.resultsTable = [[UITableView alloc] initWithFrame:CGRectMake(0, 44, self.view.bounds.size.width, 220)
                                                     style:UITableViewStylePlain];
    self.resultsTable.delegate = self;
    self.resultsTable.dataSource = self;
    self.resultsTable.hidden = YES;
    self.resultsTable.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.resultsTable.layer.shadowColor = [UIColor blackColor].CGColor;
    self.resultsTable.layer.shadowOffset = CGSizeMake(0, 2);
    self.resultsTable.layer.shadowOpacity = 0.15;
    self.resultsTable.layer.shadowRadius = 4;
    [self.view addSubview:self.resultsTable];

    self.bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 120)];
    self.bottomBar.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.96];
    self.bottomBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.bottomBar];

    self.coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 10, self.view.bounds.size.width - 32, 18)];
    self.coordLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.coordLabel.textColor = [UIColor secondaryLabelColor];
    self.coordLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.bottomBar addSubview:self.coordLabel];

    self.nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 30, self.view.bounds.size.width - 32, 20)];
    self.nameLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.nameLabel.text = self.currentName.length ? self.currentName : @"拖动地图调整位置";
    self.nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.bottomBar addSubview:self.nameLabel];

    UIButton *confirm = [UIButton buttonWithType:UIButtonTypeSystem];
    confirm.frame = CGRectMake(16, 58, self.view.bounds.size.width - 32, 48);
    confirm.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    confirm.backgroundColor = [UIColor systemBlueColor];
    [confirm setTitle:@"确认此位置" forState:UIControlStateNormal];
    [confirm setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    confirm.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    confirm.layer.cornerRadius = 12;
    [confirm addTarget:self action:@selector(confirmTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:confirm];

    [self updateCoordLabel];
    [self reverseGeocode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat topSafe = 0, bottomSafe = 0;
    if (@available(iOS 11.0, *)) {
        topSafe = self.view.safeAreaInsets.top;
        bottomSafe = self.view.safeAreaInsets.bottom;
    }

    self.searchBar.frame = CGRectMake(0, topSafe, self.view.bounds.size.width, 44);

    CGRect rt = self.resultsTable.frame;
    rt.origin.y = CGRectGetMaxY(self.searchBar.frame);
    self.resultsTable.frame = rt;

    CGRect bb = self.bottomBar.frame;
    bb.origin.y = self.view.bounds.size.height - bb.size.height - bottomSafe;
    self.bottomBar.frame = bb;

    // 十字标固定在"可见地图区域"中心
    CGFloat visibleTop = CGRectGetMaxY(self.searchBar.frame);
    CGFloat visibleBottom = CGRectGetMinY(self.bottomBar.frame);
    self.pin.center = CGPointMake(self.view.bounds.size.width / 2.0,
                                  (visibleTop + visibleBottom) / 2.0);
}

- (UIImage *)pinImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(32, 32), NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();

    CGContextSetFillColorWithColor(ctx, [[UIColor systemRedColor] colorWithAlphaComponent:0.92].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(8, 3, 16, 16));

    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(12, 7, 8, 8));

    CGContextMoveToPoint(ctx, 10, 17);
    CGContextAddLineToPoint(ctx, 16, 29);
    CGContextAddLineToPoint(ctx, 22, 17);
    CGContextClosePath(ctx);
    CGContextSetFillColorWithColor(ctx, [[UIColor systemRedColor] colorWithAlphaComponent:0.92].CGColor);
    CGContextFillPath(ctx);

    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)updateCoordLabel {
    CLLocationCoordinate2D wgs = CLXGCJ02ToWGS84(self.currentCoord);
    self.coordLabel.text = [NSString stringWithFormat:@"WGS-84 %.6f, %.6f  ·  GCJ-02 %.6f, %.6f",
                            wgs.latitude, wgs.longitude,
                            self.currentCoord.latitude, self.currentCoord.longitude];
}

#pragma mark - Map

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    self.currentCoord = mapView.centerCoordinate;
    [self updateCoordLabel];

    // 逆地理有速率限制，拖动时做 0.6s 防抖
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(reverseGeocode) object:nil];
    [self performSelector:@selector(reverseGeocode) withObject:nil afterDelay:0.6];
}

#pragma mark - Geocode

- (void)reverseGeocode {
    CLLocationCoordinate2D wgs = CLXGCJ02ToWGS84(self.currentCoord);
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:wgs.latitude longitude:wgs.longitude];
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    __weak typeof(self) weakSelf = self;
    [geocoder reverseGeocodeLocation:loc completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || !placemarks.count) return;
        CLPlacemark *pm = placemarks.firstObject;
        NSMutableString *name = [NSMutableString string];
        if (pm.name.length) [name appendString:pm.name];
        if (pm.locality.length && ![name containsString:pm.locality]) {
            [name appendFormat:@" %@", pm.locality];
        }
        if (pm.subLocality.length && ![name containsString:pm.subLocality]) {
            [name appendFormat:@" %@", pm.subLocality];
        }
        if (!name.length) [name appendString:@"未知位置"];

        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.currentName = name;
            weakSelf.nameLabel.text = name;
        });
    }];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length < 1) {
        self.searchResults = nil;
        self.resultsTable.hidden = YES;
        return;
    }
    [self performSearch:searchText];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)performSearch:(NSString *)query {
    MKLocalSearchRequest *req = [[MKLocalSearchRequest alloc] init];
    req.naturalLanguageQuery = query;
    req.region = self.mapView.region;

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:req];
    __weak typeof(self) weakSelf = self;
    [search startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.searchResults = response.mapItems;
            weakSelf.resultsTable.hidden = (weakSelf.searchResults.count == 0);
            [weakSelf.resultsTable reloadData];
        });
    }];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.searchResults.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"c"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
    }
    MKMapItem *item = self.searchResults[indexPath.row];
    cell.textLabel.text = item.name;
    cell.detailTextLabel.text = item.placemark.title ?: @"";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    MKMapItem *item = self.searchResults[indexPath.row];
    CLLocationCoordinate2D coord = item.placemark.coordinate;

    self.currentCoord = coord;
    self.currentName = item.name;
    self.nameLabel.text = item.name;
    [self updateCoordLabel];
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(coord, 400, 400) animated:YES];

    self.searchResults = nil;
    self.resultsTable.hidden = YES;
    [self.searchBar resignFirstResponder];
    self.searchBar.text = item.name;
}

#pragma mark - Confirm

- (void)confirmTapped {
    // 地图拿到的是 GCJ-02，统一转成 WGS-84 存储；
    // 输出时再按目标层需要转回 GCJ-02。
    CLLocationCoordinate2D wgs = CLXGCJ02ToWGS84(self.currentCoord);
    if (self.onLocationPicked) {
        self.onLocationPicked(wgs, self.currentName.length ? self.currentName : @"自定义位置");
    }
    [self.navigationController popViewControllerAnimated:YES];
}

@end
