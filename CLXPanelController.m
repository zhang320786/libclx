#import "CLXPanelController.h"
#import "CLXMapController.h"
#import "CLXStore.h"
#import "CLXSession.h"
#import "CLXShared.h"

typedef NS_ENUM(NSInteger, CLXPanelSection) {
    CLXPanelSectionMaster = 0,
    CLXPanelSectionPlace,
    CLXPanelSectionMotion,
    CLXPanelSectionCompat,
    CLXPanelSectionDebug,
    CLXPanelSectionCount
};

@interface CLXPanelController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UILabel *statusLabel;
- (void)showDiagnostics;
@end

@implementation CLXPanelController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"位置";

    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                                          target:self
                                                                          action:@selector(close)];
    self.navigationItem.rightBarButtonItem = done;
    // 诊断入口放左上角，不用滚到底去找
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"诊断"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(showDiagnostics)];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    [self buildHeader];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [CLXStore invalidate];
    [self refreshHeader];
    [self.tableView reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - Header

- (void)buildHeader {
    CGFloat w = self.view.bounds.size.width;
    if (w <= 0) w = [UIScreen mainScreen].bounds.size.width;

    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, 96)];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 14, w - 40, 22)];
    title.text = @"位置工具";
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [header addSubview:title];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 40, w - 40, 44)];
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    [header addSubview:self.statusLabel];

    self.tableView.tableHeaderView = header;
}

- (void)refreshHeader {
    CLXSession *session = [CLXSession shared];
    NSDictionary *d = [session diagnostics];

    NSString *state = [session isActive] ? @"已接管" : ([CLXStore enabled] ? @"已开启（未取到定位）" : @"未开启");
    NSMutableString *text = [NSMutableString stringWithFormat:@"状态：%@", state];

    if (d[@"outLat"]) {
        [text appendFormat:@"\n输出：%.6f, %.6f  ±%.0fm  %.1fm/s",
         [d[@"outLat"] doubleValue], [d[@"outLng"] doubleValue],
         [d[@"outAcc"] doubleValue], [d[@"outSpeed"] doubleValue]];
    } else if (d[@"realLat"]) {
        [text appendFormat:@"\n真实：%.6f, %.6f", [d[@"realLat"] doubleValue], [d[@"realLng"] doubleValue]];
    }
    self.statusLabel.text = text;
    self.statusLabel.numberOfLines = 3;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return CLXPanelSectionCount;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case CLXPanelSectionMaster: return 2;
        case CLXPanelSectionPlace:  return 2;
        case CLXPanelSectionMotion: return 3;
        case CLXPanelSectionCompat: return 4;
        case CLXPanelSectionDebug:  return 2;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case CLXPanelSectionMaster: return nil;
        case CLXPanelSectionPlace:  return @"目标位置";
        case CLXPanelSectionMotion: return @"行为";
        case CLXPanelSectionCompat: return @"兼容性";
        case CLXPanelSectionDebug:  return @"诊断";
        default: return nil;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    switch (section) {
        case CLXPanelSectionMaster:
            return @"开启后，本进程内所有定位结果都会被替换为目标点。\\n诊断日志写入 App 沙箱 Library/Caches/.dbg，日志量大时自动截断。";
        case CLXPanelSectionMotion:
            return @"步行/驾车模式会从上一次真实位置匀速移动过去，避免出现超大瞬时速度记录。\n步行仅对 3km 内生效、驾车 60km 内生效；超出范围自动切换。";
        case CLXPanelSectionCompat:
            return @"严格模式：打卡地点仍未变化时打开（会接管所有 CLLocation 取点）。\n深度模式：严格模式仍无效时打开（接管 WWKLocation* 业务层取点）。\n两项都会增加异常风险，按需开启。";
        case CLXPanelSectionDebug:
            return @"诊断日志写入 App 沙箱 Library/Caches/.dbg，可用文件管理器查看。";
        default:
            return nil;
    }
}

- (UITableViewCell *)cellWithTitle:(NSString *)title detail:(NSString *)detail {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.text = detail;
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    return cell;
}

- (UITableViewCell *)switchCellWithTitle:(NSString *)title on:(BOOL)on action:(SEL)action {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = title;
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];

    UISwitch *sw = [[UISwitch alloc] init];
    sw.on = on;
    [sw addTarget:self action:action forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = sw;
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger s = indexPath.section;
    NSInteger r = indexPath.row;

    if (s == CLXPanelSectionMaster) {
        if (r == 0) {
            return [self switchCellWithTitle:@"启用虚拟定位" on:[CLXStore enabled] action:@selector(toggleEnabled:)];
        }
        return [self switchCellWithTitle:@"诊断日志" on:[CLXStore diagnosticsEnabled] action:@selector(toggleDiag:)];
    }

    if (s == CLXPanelSectionPlace) {
        if (r == 0) {
            NSString *name = [CLXStore targetName];
            CLLocationCoordinate2D t = [CLXStore target];
            NSString *detail = name.length ? name : (CLXCoordinateValid(t) ? @"已设置" : @"未设置");
            UITableViewCell *cell = [self cellWithTitle:@"选择目标位置" detail:detail];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        double alt = [CLXStore altitude];
        NSString *detail = (alt > 0) ? [NSString stringWithFormat:@"%.0f m", alt] : @"跟随真实海拔";
        UITableViewCell *cell = [self cellWithTitle:@"海拔高度" detail:detail];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (s == CLXPanelSectionMotion) {
        if (r == 0) {
            NSArray *names = @[@"瞬移", @"步行", @"驾车"];
            UITableViewCell *cell = [self cellWithTitle:@"移动方式" detail:names[[CLXStore travelMode]]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        if (r == 1) {
            NSArray *names = @[@"自动", @"室外", @"室内"];
            UITableViewCell *cell = [self cellWithTitle:@"定位精度" detail:names[[CLXStore accuracyProfile]]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }
        NSArray *names = @[@"自动", @"强制 GCJ-02", @"强制 WGS-84"];
        UITableViewCell *cell = [self cellWithTitle:@"坐标系" detail:names[[CLXStore coordinateMode]]];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }

    if (s == CLXPanelSectionCompat) {
        if (r == 0) return [self switchCellWithTitle:@"严格模式" on:[CLXStore strictMode] action:@selector(toggleStrict:)];
        if (r == 1) return [self switchCellWithTitle:@"深度模式" on:[CLXStore deepMode] action:@selector(toggleDeep:)];
        if (r == 2) return [self switchCellWithTitle:@"屏蔽 WiFi 指纹" on:[CLXStore hideWiFi] action:@selector(toggleWiFi:)];
        return [self switchCellWithTitle:@"隐藏越狱环境" on:[CLXStore antiDetect] action:@selector(toggleGuard:)];
    }

    // Debug
    if (r == 0) {
        UITableViewCell *cell = [self cellWithTitle:@"查看诊断信息" detail:@""];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    UITableViewCell *cell = [self cellWithTitle:@"复位到真实位置" detail:@""];
    cell.textLabel.textColor = [UIColor systemRedColor];
    return cell;
}

#pragma mark - Actions

- (void)toggleEnabled:(UISwitch *)sw {
    [CLXStore setEnabled:sw.on];
    [CLXStore invalidate];
    [self refreshHeader];
}

- (void)toggleStrict:(UISwitch *)sw {
    [CLXStore setStrictMode:sw.on];
    [CLXStore invalidate];
}

- (void)toggleDeep:(UISwitch *)sw {
    [CLXStore setDeepMode:sw.on];
    [CLXStore invalidate];
    if (sw.on) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启生效"
                                                                       message:@"深度模式需要在启动时扫描类，请重启应用后再打卡。"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)toggleWiFi:(UISwitch *)sw {
    [CLXStore setHideWiFi:sw.on];
    [CLXStore invalidate];
}

- (void)toggleGuard:(UISwitch *)sw {
    [CLXStore setAntiDetect:sw.on];
    [CLXStore invalidate];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重启生效"
                                                                   message:@"环境隐藏在进程启动时安装，请重启应用。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)toggleDiag:(UISwitch *)sw {
    [CLXStore setDiagnosticsEnabled:sw.on];
    [CLXStore invalidate];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSInteger s = indexPath.section;
    NSInteger r = indexPath.row;

    if (s == CLXPanelSectionPlace) {
        if (r == 0) [self openMapPicker];
        else       [self editAltitude];
        return;
    }

    if (s == CLXPanelSectionMotion) {
        if (r == 0) {
            [self chooseFrom:@[@"瞬移", @"步行", @"驾车"]
                       title:@"移动方式"
                     current:[CLXStore travelMode]
                      apply:^(NSInteger idx) { [CLXStore setTravelMode:(CLXTravelMode)idx]; }];
        } else if (r == 1) {
            [self chooseFrom:@[@"自动", @"室外", @"室内"]
                       title:@"定位精度"
                     current:[CLXStore accuracyProfile]
                      apply:^(NSInteger idx) { [CLXStore setAccuracyProfile:(CLXAccuracyProfile)idx]; }];
        } else {
            [self chooseFrom:@[@"自动", @"强制 GCJ-02", @"强制 WGS-84"]
                       title:@"坐标系"
                     current:[CLXStore coordinateMode]
                      apply:^(NSInteger idx) { [CLXStore setCoordinateMode:idx]; }];
        }
        return;
    }

    if (s == CLXPanelSectionDebug) {
        if (r == 0) [self showDiagnostics];
        if (r == 1) [self confirmReset];
    }
}

- (void)chooseFrom:(NSArray<NSString *> *)options
             title:(NSString *)title
           current:(NSInteger)current
             apply:(void (^)(NSInteger))apply {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSInteger i = 0; i < options.count; i++) {
        NSString *label = (i == current) ? [NSString stringWithFormat:@"✓ %@", options[i]] : options[i];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            apply(i);
            [CLXStore invalidate];
            [self refreshHeader];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, self.view.bounds.size.height / 2, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)openMapPicker {
    CLXMapController *map = [[CLXMapController alloc] init];
    __weak typeof(self) weakSelf = self;
    map.onLocationPicked = ^(CLLocationCoordinate2D coord, NSString *name) {
        [CLXStore setTarget:coord];
        [CLXStore setTargetName:name];
        [CLXStore invalidate];
        [weakSelf refreshHeader];
        [weakSelf.tableView reloadData];
    };
    [self.navigationController pushViewController:map animated:YES];
}

- (void)editAltitude {
    double cur = [CLXStore altitude];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"海拔高度"
                                                                   message:@"单位：米，填 0 跟随真实海拔"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = @"0";
        tf.text = (cur > 0) ? [NSString stringWithFormat:@"%.0f", cur] : @"0";
        tf.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        double v = [alert.textFields.firstObject.text doubleValue];
        [CLXStore setAltitude:(v > 0 ? v : 0)];
        [CLXStore invalidate];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showDiagnostics {
    NSDictionary *d = [[CLXSession shared] diagnostics];
    NSMutableString *text = [NSMutableString string];
    NSArray *order = @[@"enabled", @"active", @"hasReal", @"realLat", @"realLng", @"realAlt", @"realAcc",
                       @"targetLat", @"targetLng", @"targetGCJLat", @"targetGCJLng",
                       @"outLat", @"outLng", @"outGCJLat", @"outGCJLng", @"outAcc", @"outSpeed",
                       @"dist", @"callbacks", @"lastCbAgo"];
    for (NSString *k in order) {
        if (d[k]) [text appendFormat:@"%@ = %@\n", k, d[k]];
    }
    if (!text.length) [text appendString:@"暂无数据"];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"诊断信息"
                                                                   message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = text;
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)confirmReset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"复位"
                                                                   message:@"清除目标点并关闭接管，恢复真实定位。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"复位" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[CLXSession shared] clearTarget];
        [self refreshHeader];
        [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
