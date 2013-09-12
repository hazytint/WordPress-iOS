//
//  PostMediaViewController.m
//  WordPress
//
//  Created by Chris Boyd on 8/26/10.
//  Code is poetry.
//

#import "PostMediaViewController.h"
#import "EditPostViewController_Internal.h"
#import "Post.h"
#import <ImageIO/ImageIO.h>
#import "WPPopoverBackgroundView.h"

#define TAG_ACTIONSHEET_PHOTO 1
#define TAG_ACTIONSHEET_VIDEO 2
#define TAG_ACTIONSHEET_PHOTO_SELECTION_PROMPT 3
#define NUMBERS	@"0123456789"


@interface PostMediaViewController ()

@property (nonatomic, strong) AbstractPost *apost;
@property (nonatomic, weak) UIActionSheet *addMediaActionSheet;

- (void)getMetadataFromAssetForURL:(NSURL *)url;
- (UITableViewCell *)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath;
@end

@implementation PostMediaViewController {
    CGRect actionSheetRect;
    UIAlertView *currentAlert;
    
    BOOL _dismissOnCancel;
    BOOL _hasPromptedToAddPhotos;
}
@synthesize table, addMediaButton, hasPhotos, hasVideos, isAddingMedia, photos, videos, addPopover, picker;
@synthesize isShowingMediaPickerActionSheet, currentOrientation, isShowingChangeOrientationActionSheet, spinner;
@synthesize currentImage, currentImageMetadata, currentVideo, isLibraryMedia, didChangeOrientationDuringRecord, messageLabel;
@synthesize postDetailViewController, postID, blogURL, bottomToolbar;
@synthesize isShowingResizeActionSheet, isShowingCustomSizeAlert, videoEnabled, currentUpload, videoPressCheckBlogURL, isCheckingVideoCapability, uniqueID;
@synthesize currentActionSheet;

#pragma mark -
#pragma mark Lifecycle Methods

- (void)dealloc {
    picker.delegate = nil;
    addPopover.delegate = nil;
}

- (id)initWithPost:(AbstractPost *)aPost {
    self = [super init];
    if (self) {
        self.apost = aPost;
    }
    return self;
}

- (void)initObjects {
	self.photos = [[NSMutableArray alloc] init];
	self.videos = [[NSMutableArray alloc] init];
    actionSheetRect = CGRectZero;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
		[self initObjects];
    }
    return self;
}

- (void)viewDidLoad {
    [FileLogger log:@"%@ %@", self, NSStringFromSelector(_cmd)];
    [super viewDidLoad];
    
    if (IS_IOS7) {
        self.table.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 10)];
    }
    
    self.title = NSLocalizedString(@"Media", nil);
	
	self.currentOrientation = [self interpretOrientation:[UIDevice currentDevice].orientation];
		
	[self initObjects];
	self.videoEnabled = YES;
    [self checkVideoPressEnabled];
    
    if (IS_IOS7) {
        [self customizeForiOS7];
    }
	
    [self addNotifications];    
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (IS_IOS7 && !_hasPromptedToAddPhotos) {
        id <NSFetchedResultsSectionInfo> sectionInfo = nil;
        sectionInfo = [[self.resultsController sections] objectAtIndex:0];
        if ([sectionInfo numberOfObjects] == 0) {
            _dismissOnCancel = true;;
            [self tappedAddButton];
        }
    }
    _hasPromptedToAddPhotos = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    if (_addMediaActionSheet) {
        [_addMediaActionSheet dismissWithClickedButtonIndex:_addMediaActionSheet.cancelButtonIndex animated:true];
    }
}

- (NSString *)statsPrefix
{
    if (_statsPrefix == nil)
        return @"Post Detail";
    else
        return _statsPrefix;
}

- (void)customizeForiOS7
{
    UIImage *image = [UIImage imageNamed:@"icon-posts-add"];
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, image.size.width, image.size.height)];
    [button setImage:image forState:UIControlStateNormal];
    [button addTarget:self action:@selector(tappedAddButton) forControlEvents:UIControlEventTouchUpInside];
    UIBarButtonItem *addButton = [[UIBarButtonItem alloc] initWithCustomView:button];

    [WPStyleGuide setRightBarButtonItemWithCorrectSpacing:addButton forNavigationItem:self.navigationItem];
}

- (void)tappedAddButton
{
    if (_addMediaActionSheet != nil || self.isShowingResizeActionSheet == YES)
        return;

    if (addPopover != nil) {
        [addPopover dismissPopoverAnimated:YES];
        [[CPopoverManager instance] setCurrentPopoverController:NULL];
        addPopover = nil;
    }
    
    UIActionSheet *addMediaActionSheet;
    
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        if ([self isDeviceSupportVideoAndVideoPressEnabled]) {
            addMediaActionSheet = [[UIActionSheet alloc] initWithTitle:@"" delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Add Photo From Library", nil), NSLocalizedString(@"Take Photo", nil), NSLocalizedString(@"Add Video from Library", @""), NSLocalizedString(@"Record Video", @""),nil];
            _addMediaActionSheet = addMediaActionSheet;
            
        } else {
            addMediaActionSheet = [[UIActionSheet alloc] initWithTitle:@"" delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Add Photo From Library", nil), NSLocalizedString(@"Take Photo", nil), nil];
            _addMediaActionSheet = addMediaActionSheet;
        }
    } else {
        addMediaActionSheet = [[UIActionSheet alloc] initWithTitle:@"" delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", nil) destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Add Photo From Library", nil), nil];
        _addMediaActionSheet = addMediaActionSheet;
    }
    
    _addMediaActionSheet.tag = TAG_ACTIONSHEET_PHOTO_SELECTION_PROMPT;
    if (IS_IPAD) {
        [_addMediaActionSheet showFromBarButtonItem:[self.navigationItem.rightBarButtonItems objectAtIndex:1] animated:YES];
    } else {
        [_addMediaActionSheet showInView:self.view];
    }
}


- (void)addNotifications {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaDidUploadSuccessfully:) name:VideoUploadSuccessful object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaDidUploadSuccessfully:) name:ImageUploadSuccessful object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaUploadFailed:) name:VideoUploadFailed object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(mediaUploadFailed:) name:ImageUploadFailed object:nil];
}

- (void)removeNotifications{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
}

- (void)viewDidUnload {
    [self removeNotifications];
    self.table = nil;
    self.addMediaButton = nil;
    self.spinner = nil;
    self.messageLabel = nil;
    self.bottomToolbar = nil;
    self.addPopover = nil;
    self.customSizeAlert = nil;
    self.currentActionSheet = nil;
    
	[super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return [super shouldAutorotateToInterfaceOrientation:interfaceOrientation];
}

- (Post *)post {
    if ([self.apost isKindOfClass:[Post class]]) {
        return (Post *)self.apost;
    }
    return nil;
}

#pragma mark -
#pragma mark Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[self.resultsController sections] count];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = nil;
    sectionInfo = [[self.resultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
	}
    
    [self configureCell:cell atIndexPath:indexPath];
    
    return cell;
}

- (UITableViewCell *)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
	Media *media = [self.resultsController objectAtIndexPath:indexPath];
    cell.imageView.image = [UIImage imageWithData:media.thumbnail];
	NSString *filesizeString = nil;
    if([media.filesize floatValue] > 1024)
        filesizeString = [NSString stringWithFormat:@"%.2f MB", ([media.filesize floatValue]/1024)];
    else
        filesizeString = [NSString stringWithFormat:@"%.2f KB", [media.filesize floatValue]];
    
    if(media.title != nil)
        cell.textLabel.text = media.title;
    else
        cell.textLabel.text = media.filename;

    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    if (media.remoteStatus == MediaRemoteStatusPushing) {
        cell.detailTextLabel.text = [NSString stringWithFormat:NSLocalizedString(@"Uploading: %.1f%%. Tap to cancel.", @""), media.progress * 100.0];
    } else if (media.remoteStatus == MediaRemoteStatusProcessing) {
        cell.detailTextLabel.text = NSLocalizedString(@"Preparing for upload...", @"");
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (media.remoteStatus == MediaRemoteStatusFailed) {
        cell.detailTextLabel.text = NSLocalizedString(@"Upload failed - tap to retry.", @"");
    } else {
        if ([media.mediaType isEqualToString:@"image"]) {
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%dx%d %@", 
                                         [media.width intValue], [media.height intValue], filesizeString];        
        } else if ([media.mediaType isEqualToString:@"video"]) {
            NSNumber *valueForDisplay = [NSNumber numberWithDouble:[media.length doubleValue]];
            NSNumber *days = [NSNumber numberWithDouble:
                              ([valueForDisplay doubleValue] / 86400)];
            NSNumber *hours = [NSNumber numberWithDouble:
                               (([valueForDisplay doubleValue] / 3600) -
                                ([days intValue] * 24))];
            NSNumber *minutes = [NSNumber numberWithDouble:
                                 (([valueForDisplay doubleValue] / 60) -
                                  ([days intValue] * 24 * 60) -
                                  ([hours intValue] * 60))];
            NSNumber *seconds = [NSNumber numberWithInt:([valueForDisplay intValue] % 60)];
            
            if([media.filesize floatValue] > 1024)
                filesizeString = [NSString stringWithFormat:@"%.2f MB", ([media.filesize floatValue]/1024)];
            else
                filesizeString = [NSString stringWithFormat:@"%.2f KB", [media.filesize floatValue]];
            
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%02d:%02d:%02d %@",
                                         [hours intValue],
                                         [minutes intValue],
                                         [seconds intValue], 
                                         filesizeString];
        }
    }

	[cell.imageView setBounds:CGRectMake(0.0f, 0.0f, 75.0f, 75.0f)];
	[cell.imageView setClipsToBounds:YES];
	[cell.imageView setFrame:CGRectMake(0.0f, 0.0f, 75.0f, 75.0f)];
	[cell.imageView setContentMode:UIViewContentModeScaleAspectFill];
    
	filesizeString = nil;
    
    [WPStyleGuide configureTableViewCell:cell];
    
    return cell;
}

- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath: (NSIndexPath *) indexPath {
	return 75.0f;
}

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    Media *media = [self.resultsController objectAtIndexPath:indexPath];

    if (media.remoteStatus == MediaRemoteStatusFailed) {
        [media uploadWithSuccess:^{
            if (([media isDeleted])) {
                NSLog(@"Media deleted while uploading (%@)", media);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldInsertMediaBelow" object:media];
            [media save];
        } failure:^(NSError *error) {
            // User canceled upload
            if (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) {
                return;
            }
            [WPError showAlertWithError:error title:NSLocalizedString(@"Upload failed", @"")];
        }];
    } else if (media.remoteStatus == MediaRemoteStatusPushing) {
        [media cancelUpload];
    } else if (media.remoteStatus == MediaRemoteStatusProcessing) {
        // Do nothing. See trac #1508
    } else {
        MediaObjectViewController *mediaView = [[MediaObjectViewController alloc] initWithNibName:@"MediaObjectView" bundle:nil];
        [mediaView setMedia:media];

        if(IS_IPAD == YES) {
			mediaView.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
			mediaView.modalPresentationStyle = UIModalPresentationFormSheet;
			
            [self presentViewController:mediaView animated:YES completion:nil];
		}
        else {
            [self.postDetailViewController.navigationController pushViewController:mediaView animated:YES];
        }
    }

	[tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(void)tableView:(UITableView*)tableView willBeginEditingRowAtIndexPath:(NSIndexPath *)indexPath {
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
	// If row is deleted, remove it from the list.
	if (editingStyle == UITableViewCellEditingStyleDelete)
	{
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldRemoveMedia" object:[self.resultsController objectAtIndexPath:indexPath]];
        Media *media = [self.resultsController objectAtIndexPath:indexPath];
        [media remove];
        [media save];
	}
}

-(NSString *)tableView:(UITableView*)tableView titleForDeleteConfirmationButtonForRowAtIndexPath:(NSIndexPath *)indexPath {
	return NSLocalizedString(@"Remove", @"");
}

//Hide unnecessary row dividers. See http://ios.trac.wordpress.org/ticket/1264
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    if ([self numberOfSectionsInTableView:tableView] == (section+1)){
        return [UIView new];
    }
    return nil;
}

#pragma mark -
#pragma mark Custom methods

- (void)scaleAndRotateImage:(UIImage *)image {
	NSLog(@"scaling and rotating image...");
}

- (IBAction)showVideoPickerActionSheet:(id)sender {
    if (currentActionSheet || addPopover) {
        return;
    }
    
    isShowingMediaPickerActionSheet = YES;
	isAddingMedia = YES;
	
	UIActionSheet *actionSheet;
	if([self isDeviceSupportVideoAndVideoPressEnabled]) {
		actionSheet = [[UIActionSheet alloc] initWithTitle:@"" 
												  delegate:self 
										 cancelButtonTitle:NSLocalizedString(@"Cancel", @"") 
									destructiveButtonTitle:nil 
										 otherButtonTitles:NSLocalizedString(@"Add Video from Library", @""),NSLocalizedString(@"Record Video", @""),nil];
	} 
	else { //device has video recording capability but VideoPress could be not enabled on
       /* isShowingMediaPickerActionSheet = NO;
        [self pickPhotoFromPhotoLibrary:sender];
        return;*/
		isShowingMediaPickerActionSheet = NO;
		NSString *faultString = NSLocalizedString(@"You can upload videos to your blog with VideoPress. Would you like to learn more about VideoPress now?", @"");
        if (currentAlert == nil) {
            UIAlertView *uploadAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"VideoPress", @"")
                                                                  message:faultString
                                                                 delegate:self
                                                        cancelButtonTitle:NSLocalizedString(@"No", @"") otherButtonTitles:nil];
            [uploadAlert addButtonWithTitle:NSLocalizedString(@"Yes", @"")];
            uploadAlert.tag = 101;
            [uploadAlert show];
            currentAlert = uploadAlert;
        }
		return;
	}
	
    actionSheet.tag = TAG_ACTIONSHEET_VIDEO;
    actionSheet.actionSheetStyle = UIActionSheetStyleDefault;
    if (IS_IPAD) {
        if (IS_IOS7) {
            [actionSheet showFromBarButtonItem:[self.navigationItem.rightBarButtonItems objectAtIndex:1] animated:YES];
        } else {
            [actionSheet showFromBarButtonItem:postDetailViewController.movieButton animated:YES];
        }
    } else {
        [actionSheet showInView:postDetailViewController.view];
    }

    WordPressAppDelegate *appDelegate = (WordPressAppDelegate*)[[UIApplication sharedApplication] delegate];
    [appDelegate setAlertRunning:YES];
	
}

- (IBAction)showPhotoPickerActionSheet:(id)sender {
    [self showPhotoPickerActionSheet:sender fromRect:CGRectZero isFeaturedImage:NO];
}

- (IBAction)showPhotoPickerActionSheet:(id)sender fromRect:(CGRect)rect isFeaturedImage:(BOOL)featuredImage {
    if (currentActionSheet || addPopover) {
        return;
    }
    
    isPickingFeaturedImage = featuredImage;
    isShowingMediaPickerActionSheet = YES;
	isAddingMedia = YES;
	
	UIActionSheet *actionSheet;
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
		actionSheet = [[UIActionSheet alloc] initWithTitle:@"" 
												  delegate:self 
										 cancelButtonTitle:NSLocalizedString(@"Cancel", @"") 
									destructiveButtonTitle:nil 
										 otherButtonTitles:NSLocalizedString(@"Add Photo from Library", @""),NSLocalizedString(@"Take Photo", @""),nil];
	}
	else {
        isShowingMediaPickerActionSheet = NO;
        [self pickPhotoFromPhotoLibrary:sender];
        return;
	}
	
    actionSheet.tag = TAG_ACTIONSHEET_PHOTO;
    actionSheet.actionSheetStyle = UIActionSheetStyleDefault;
    if (IS_IPAD) {
        actionSheetRect = rect;
        if (!CGRectIsEmpty(rect)) {
            [actionSheet showFromRect:rect inView:self.postDetailViewController.postSettingsViewController.view animated:YES];
        } else {
            [actionSheet showFromBarButtonItem:postDetailViewController.photoButton animated:YES];
        }
    } else {
        if (IS_IOS7) {
            [actionSheet showInView:self.view];
        } else {
            [actionSheet showInView:postDetailViewController.view];
        }
    }
    
    WordPressAppDelegate *appDelegate = (WordPressAppDelegate*)[[UIApplication sharedApplication] delegate];
    [appDelegate setAlertRunning:YES];
	
}


#pragma mark -
#pragma mark UIPopover Delegate Methods

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController {
    addPopover.delegate = nil;
    addPopover = nil;
}


#pragma mark -
#pragma mark Action Sheet Delegate Methods

- (void)didPresentActionSheet:(UIActionSheet *)actionSheet {
    self.currentActionSheet = actionSheet;
}

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {

    _addMediaActionSheet = nil;
    
    if (actionSheet.tag == TAG_ACTIONSHEET_PHOTO_SELECTION_PROMPT) {
        [self processPhotoPickerActionSheet:actionSheet didDismissWithButtonIndex:buttonIndex];
        return;
    }
    
	if(isShowingMediaPickerActionSheet == YES) {
		switch (actionSheet.numberOfButtons) {
			case 2:
				if(buttonIndex == 0)
					[self pickPhotoFromPhotoLibrary:actionSheet];
				else {
					self.isAddingMedia = NO;
				}
				break;
			case 3:
				if(buttonIndex == 0) {
					[self pickPhotoFromPhotoLibrary:actionSheet];
				}
				else if(buttonIndex == 1) {
                    if (actionSheet.tag == TAG_ACTIONSHEET_VIDEO) {
                        [self pickVideoFromCamera:actionSheet];
                    } else {
                        [self pickPhotoFromCamera:actionSheet];
                    }
				}
				else {
					self.isAddingMedia = NO;
				}
				break;
			default:
				break;
		}
		isShowingMediaPickerActionSheet = NO;
	}
	else if(isShowingChangeOrientationActionSheet == YES) {
		switch (buttonIndex) {
			case 0:
				self.currentOrientation = kPortrait;
				break;
			case 1:
				self.currentOrientation = kLandscape;
				break;
			default:
				self.currentOrientation = kPortrait;
				break;
		}
		[self processRecordedVideo];
		self.isShowingChangeOrientationActionSheet = NO;
	}
	else if(isShowingResizeActionSheet == YES) {
        if (actionSheet.cancelButtonIndex != buttonIndex) {
            switch (buttonIndex) {
                case 0:
                    if (actionSheet.numberOfButtons == 3)
                        [self useImage:[self resizeImage:currentImage toSize:kResizeOriginal]];
                    else
                        [self useImage:[self resizeImage:currentImage toSize:kResizeSmall]];
                    break;
                case 1:
                    if (actionSheet.numberOfButtons == 3)
                        [self showCustomSizeAlert];
                    else if (actionSheet.numberOfButtons == 4)
                        [self useImage:[self resizeImage:currentImage toSize:kResizeOriginal]];
                    else
                        [self useImage:[self resizeImage:currentImage toSize:kResizeMedium]];
                    break;
                case 2:
                    if (actionSheet.numberOfButtons == 4)
                        [self showCustomSizeAlert];
                    else if (actionSheet.numberOfButtons == 5)
                        [self useImage:[self resizeImage:currentImage toSize:kResizeOriginal]];
                    else
                        [self useImage:[self resizeImage:currentImage toSize:kResizeLarge]];
                    break;
                case 3:
                    if (actionSheet.numberOfButtons == 5)
                        [self showCustomSizeAlert];
                    else
                        [self useImage:[self resizeImage:currentImage toSize:kResizeOriginal]];
                    break;
                case 4: 
                    [self showCustomSizeAlert]; 
                    break;
            }
        }
		self.isShowingResizeActionSheet = NO;
	}
    
    WordPressAppDelegate *appDelegate = (WordPressAppDelegate*)[[UIApplication sharedApplication] delegate];
    [appDelegate setAlertRunning:NO];
    
    self.currentActionSheet = nil;
}

- (void)processPhotoPickerActionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex {
    
    UIActionSheet *savedCurrentActionSheet = currentActionSheet;
    currentActionSheet = nil;
    NSString *buttonTitle = [actionSheet buttonTitleAtIndex:buttonIndex];
    
    if (IS_IOS7 && [buttonTitle isEqualToString:NSLocalizedString(@"Cancel", nil)] && _dismissOnCancel) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    if ([buttonTitle isEqualToString:NSLocalizedString(@"Add Photo From Library", nil)]) {
        [WPMobileStats flagProperty:StatsPropertyPostDetailClickedAddPhoto forEvent:[self formattedStatEventString:StatsEventPostDetailClosedEditor]];
        [self pickPhotoFromPhotoLibrary:nil];
    } else if ([buttonTitle isEqualToString:NSLocalizedString(@"Take Photo", nil)]) {
        [WPMobileStats flagProperty:StatsPropertyPostDetailClickedAddPhoto forEvent:[self formattedStatEventString:StatsEventPostDetailClosedEditor]];
        [self pickPhotoFromCamera:nil];
    } else if ([buttonTitle isEqualToString:NSLocalizedString(@"Add Video from Library", nil)]) {
        [WPMobileStats flagProperty:StatsPropertyPostDetailClickedAddVideo forEvent:[self formattedStatEventString:StatsEventPostDetailClosedEditor]];
        actionSheet.tag = TAG_ACTIONSHEET_VIDEO;
        [self pickPhotoFromPhotoLibrary:actionSheet];
    } else if ([buttonTitle isEqualToString:NSLocalizedString(@"Record Video", nil)]) {
        [WPMobileStats flagProperty:StatsPropertyPostDetailClickedAddVideo forEvent:[self formattedStatEventString:StatsEventPostDetailClosedEditor]];
        [self pickVideoFromCamera:actionSheet];
    } else {
        //
        currentActionSheet = savedCurrentActionSheet;
    }
    _dismissOnCancel = false;
}

#pragma mark -
#pragma mark Picker Methods

- (UIImagePickerController *)resetImagePicker {
    picker.delegate = nil;
    picker = [[UIImagePickerController alloc] init];
    picker.navigationBar.translucent = NO;
	picker.delegate = self;
	picker.allowsEditing = NO;
    return picker;
}

- (void)pickPhotoFromCamera:(id)sender {
	self.currentOrientation = [self interpretOrientation:[UIDevice currentDevice].orientation];
    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self resetImagePicker];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
		picker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeImage];
        picker.modalPresentationStyle = UIModalPresentationCurrentContext;
		
        [postDetailViewController.navigationController presentViewController:picker animated:YES completion:nil];
    }
}

- (void)pickVideoFromCamera:(id)sender {
	self.currentOrientation = [self interpretOrientation:[UIDevice currentDevice].orientation];
    [self resetImagePicker];
	picker.sourceType =  UIImagePickerControllerSourceTypeCamera;
	picker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeMovie];
	picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
    picker.modalPresentationStyle = UIModalPresentationCurrentContext;
	
	if([[NSUserDefaults standardUserDefaults] objectForKey:@"video_quality_preference"] != nil) {
		NSString *quality = [[NSUserDefaults standardUserDefaults] objectForKey:@"video_quality_preference"];
		switch ([quality intValue]) {
			case 0:
				picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
				break;
			case 1:
				picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
				break;
			case 2:
				picker.videoQuality = UIImagePickerControllerQualityTypeLow;
				break;
			case 3:
				picker.videoQuality = UIImagePickerControllerQualityType640x480;
				break;
			default:
				picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
				break;
		}
	}
	
    [postDetailViewController.navigationController presentViewController:picker animated:YES completion:nil];

	/*[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(deviceDidRotate:)
												 name:@"UIDeviceOrientationDidChangeNotification" object:nil];*/
}

- (void)pickPhotoFromPhotoLibrary:(id)sender {
	UIBarButtonItem *barButton = nil;

    if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
        if (IS_IPAD && addPopover != nil) {
            [addPopover dismissPopoverAnimated:YES];
        }        
        [self resetImagePicker];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        if ([(UIView *)sender tag] == TAG_ACTIONSHEET_VIDEO) {
			barButton = postDetailViewController.movieButton;
            picker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeMovie];
			picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
            picker.modalPresentationStyle = UIModalPresentationCurrentContext;
			
			if([[NSUserDefaults standardUserDefaults] objectForKey:@"video_quality_preference"] != nil) {
				NSString *quality = [[NSUserDefaults standardUserDefaults] objectForKey:@"video_quality_preference"];
				switch ([quality intValue]) {
					case 0:
						picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
						break;
					case 1:
						picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
						break;
					case 2:
						picker.videoQuality = UIImagePickerControllerQualityTypeLow;
						break;
					case 3:
						picker.videoQuality = UIImagePickerControllerQualityType640x480;
						break;
					default:
						picker.videoQuality = UIImagePickerControllerQualityTypeMedium;
						break;
				}
			}	
        } else {
            if (isPickingFeaturedImage)
                barButton = postDetailViewController.settingsButton;
            else
                barButton = postDetailViewController.photoButton;
            picker.mediaTypes = [NSArray arrayWithObject:(NSString *)kUTTypeImage];
        }
		isLibraryMedia = YES;
		
		if(IS_IPAD == YES) {
            if (addPopover == nil) {
                addPopover = [[UIPopoverController alloc] initWithContentViewController:picker];
                addPopover.popoverBackgroundViewClass = [WPPopoverBackgroundView class];
                addPopover.delegate = self;
            }
            if (IS_IOS7) {
                // We insert a spacer into the barButtonItems so we need to grab the actual
                // bar button item otherwise there is a crash.
                barButton = [self.navigationItem.rightBarButtonItems objectAtIndex:1];
            }
            if (!CGRectIsEmpty(actionSheetRect)) {
                [addPopover presentPopoverFromRect:actionSheetRect inView:self.postDetailViewController.postSettingsViewController.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
            } else {
                [addPopover presentPopoverFromBarButtonItem:barButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
            }
            [[CPopoverManager instance] setCurrentPopoverController:addPopover];
		}
		else {
            [postDetailViewController.navigationController presentViewController:picker animated:YES completion:nil];
		}
    }
}

- (MediaOrientation)interpretOrientation:(UIDeviceOrientation)theOrientation {
	MediaOrientation result = kPortrait;
	switch (theOrientation) {
		case UIDeviceOrientationPortrait:
			result = kPortrait;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			result = kPortrait;
			break;
		case UIDeviceOrientationLandscapeLeft:
			result = kLandscape;
			break;
		case UIDeviceOrientationLandscapeRight:
			result = kLandscape;
			break;
		case UIDeviceOrientationFaceUp:
			result = kPortrait;
			break;
		case UIDeviceOrientationFaceDown:
			result = kPortrait;
			break;
		case UIDeviceOrientationUnknown:
			result = kPortrait;
			break;
	}
	
	return result;
}

- (void)showOrientationChangedActionSheet {
    if (currentActionSheet || addPopover) {
        return;
    }
    
	isShowingChangeOrientationActionSheet = YES;
	UIActionSheet *orientationActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Orientation changed during recording. Please choose which orientation to use for this video.", @"") 
																		delegate:self 
															   cancelButtonTitle:nil 
														  destructiveButtonTitle:nil 
															   otherButtonTitles:NSLocalizedString(@"Portrait", @""), NSLocalizedString(@"Landscape", @""), nil];
	[orientationActionSheet showInView:postDetailViewController.view];
}

- (void)showResizeActionSheet {
	if(self.isShowingResizeActionSheet == NO) {
		isShowingResizeActionSheet = YES;
        
        Blog *currentBlog = self.apost.blog;
        NSDictionary* predefDim = [currentBlog getImageResizeDimensions];
        CGSize smallSize =  [[predefDim objectForKey: @"smallSize"] CGSizeValue];
        CGSize mediumSize = [[predefDim objectForKey: @"mediumSize"] CGSizeValue];
        CGSize largeSize =  [[predefDim objectForKey: @"largeSize"] CGSizeValue];
        CGSize originalSize = CGSizeMake(currentImage.size.width, currentImage.size.height); //The dimensions of the image, taking orientation into account.
        
        switch (currentImage.imageOrientation) { 
            case UIImageOrientationLeft:
            case UIImageOrientationLeftMirrored:
            case UIImageOrientationRight:
            case UIImageOrientationRightMirrored:
                smallSize = CGSizeMake(smallSize.height, smallSize.width);
                mediumSize = CGSizeMake(mediumSize.height, mediumSize.width);
                largeSize = CGSizeMake(largeSize.height, largeSize.width);
                break;
            default:
                break;
        }
        
		NSString *resizeSmallStr = [NSString stringWithFormat:NSLocalizedString(@"Small (%@)", @"Small (width x height)"), [NSString stringWithFormat:@"%ix%i", (int)smallSize.width, (int)smallSize.height]];
   		NSString *resizeMediumStr = [NSString stringWithFormat:NSLocalizedString(@"Medium (%@)", @"Medium (width x height)"), [NSString stringWithFormat:@"%ix%i", (int)mediumSize.width, (int)mediumSize.height]];
        NSString *resizeLargeStr = [NSString stringWithFormat:NSLocalizedString(@"Large (%@)", @"Large (width x height)"), [NSString stringWithFormat:@"%ix%i", (int)largeSize.width, (int)largeSize.height]];
        NSString *originalSizeStr = [NSString stringWithFormat:NSLocalizedString(@"Original (%@)", @"Original (width x height)"), [NSString stringWithFormat:@"%ix%i", (int)originalSize.width, (int)originalSize.height]];
        
		UIActionSheet *resizeActionSheet;
		//NSLog(@"img dimension: %f x %f ",currentImage.size.width, currentImage.size.height );
		
		if(currentImage.size.width > largeSize.width  && currentImage.size.height > largeSize.height) {
			resizeActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Choose Image Size", @"") 
															delegate:self 
												   cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
											  destructiveButtonTitle:nil 
												   otherButtonTitles:resizeSmallStr, resizeMediumStr, resizeLargeStr, originalSizeStr, NSLocalizedString(@"Custom", @""), nil];
			
		} else if(currentImage.size.width > mediumSize.width  && currentImage.size.height > mediumSize.height) {
			resizeActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Choose Image Size", @"") 
															delegate:self 
												   cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
											  destructiveButtonTitle:nil 
												   otherButtonTitles:resizeSmallStr, resizeMediumStr, originalSizeStr, NSLocalizedString(@"Custom", @""), nil];
			
		} else if(currentImage.size.width > smallSize.width  && currentImage.size.height > smallSize.height) {
			resizeActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Choose Image Size", @"") 
															delegate:self 
												   cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
											  destructiveButtonTitle:nil 
												   otherButtonTitles:resizeSmallStr, originalSizeStr, NSLocalizedString(@"Custom", @""), nil];
		} else {
			resizeActionSheet = [[UIActionSheet alloc] initWithTitle:NSLocalizedString(@"Choose Image Size", @"") 
															delegate:self 
												   cancelButtonTitle:NSLocalizedString(@"Cancel", nil)
											  destructiveButtonTitle:nil 
												   otherButtonTitles: originalSizeStr, NSLocalizedString(@"Custom", @""), nil];
		}
		
        if (IS_IOS7) {
            if (IS_IPAD) {
                [resizeActionSheet showFromBarButtonItem:[self.navigationItem.rightBarButtonItems objectAtIndex:1] animated:YES];
            } else {
                [resizeActionSheet showInView:self.view];
            }
        } else {
            [resizeActionSheet showInView:postDetailViewController.view];
        }
	}
}

#pragma mark -
#pragma mark custom image size methods

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	//check the inserted characters: the user can use cut-and-paste instead of using the keyboard, and can insert letters and spaces
	NSCharacterSet *cs = [[NSCharacterSet characterSetWithCharactersInString:NUMBERS] invertedSet];
    NSString *filtered = [[string componentsSeparatedByCharactersInSet:cs] componentsJoinedByString:@""];
    if( [string isEqualToString:filtered] == NO ) return NO; 
	
    NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
	
	if (textField.tag == 123) {
		if ([newString intValue] > currentImage.size.width  ) {
			return NO;
		}
	} else {
		if ([newString intValue] > currentImage.size.height) {
			return NO;
		}
	}
    return YES;
}

- (void)showCustomSizeAlert {
    if (self.customSizeAlert) {
        [self.customSizeAlert dismiss];
        self.customSizeAlert = nil;
    }

    isShowingCustomSizeAlert = YES;
    
    // Check for previous width setting
    NSString *widthText = nil;
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"prefCustomImageWidth"] != nil) {
        widthText = [[NSUserDefaults standardUserDefaults] objectForKey:@"prefCustomImageWidth"];
    } else {
        widthText = [NSString stringWithFormat:@"%d", (int)currentImage.size.width];
    }
    
    NSString *heightText = nil;
    if([[NSUserDefaults standardUserDefaults] objectForKey:@"prefCustomImageHeight"] != nil) {
        heightText = [[NSUserDefaults standardUserDefaults] objectForKey:@"prefCustomImageHeight"];
    } else {
        heightText = [NSString stringWithFormat:@"%d", (int)currentImage.size.height];
    }

    CGRect frame = IS_IOS7 ? self.view.bounds : postDetailViewController.view.bounds;
    WPAlertView *alertView = [[WPAlertView alloc] initWithFrame:frame andOverlayMode:WPAlertViewOverlayModeTwoTextFieldsSideBySideTwoButtonMode];
    
    alertView.overlayTitle = NSLocalizedString(@"Custom Size", @"");
//    alertView.overlayDescription = NS Localized String(@"Provide a custom width and height for the image.", @"Alert view description for resizing an image with custom size.");
    alertView.overlayDescription = @"";
    alertView.footerDescription = nil;
    alertView.firstTextFieldPlaceholder = NSLocalizedString(@"Width", @"");
    alertView.firstTextFieldValue = widthText;
    alertView.secondTextFieldPlaceholder = NSLocalizedString(@"Height", @"");
    alertView.secondTextFieldValue = heightText;
    alertView.leftButtonText = NSLocalizedString(@"Cancel", @"Cancel button");
    alertView.rightButtonText = NSLocalizedString(@"OK", @"");
    
    alertView.firstTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alertView.secondTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alertView.firstTextField.keyboardAppearance = UIKeyboardAppearanceAlert;
    alertView.secondTextField.keyboardAppearance = UIKeyboardAppearanceAlert;
    alertView.firstTextField.keyboardType = UIKeyboardTypeNumberPad;
    alertView.secondTextField.keyboardType = UIKeyboardTypeNumberPad;
    
    alertView.button1CompletionBlock = ^(WPAlertView *overlayView){
        // Cancel
        [overlayView dismiss];
        isShowingCustomSizeAlert = NO;
        
    };
    alertView.button2CompletionBlock = ^(WPAlertView *overlayView){
        [overlayView dismiss];
        isShowingCustomSizeAlert = NO;
        
		NSNumber *width = [NSNumber numberWithInt:[overlayView.firstTextField.text intValue]];
		NSNumber *height = [NSNumber numberWithInt:[overlayView.secondTextField.text intValue]];
		
		if([width intValue] < 10)
			width = [NSNumber numberWithInt:10];
		if([height intValue] < 10)
			height = [NSNumber numberWithInt:10];
		
		overlayView.firstTextField.text = [NSString stringWithFormat:@"%@", width];
		overlayView.secondTextField.text = [NSString stringWithFormat:@"%@", height];
		
		[[NSUserDefaults standardUserDefaults] setObject:overlayView.firstTextField.text forKey:@"prefCustomImageWidth"];
		[[NSUserDefaults standardUserDefaults] setObject:overlayView.secondTextField.text forKey:@"prefCustomImageHeight"];
		
		[self useImage:[self resizeImage:currentImage width:[width floatValue] height:[height floatValue]]];
    };
    
    alertView.alpha = 0.0;
    
    if (IS_IOS7) {
        [self.view addSubview:alertView];
    } else {
        alertView.hideBackgroundView = YES;
        alertView.firstTextField.keyboardAppearance = UIKeyboardAppearanceDefault;
        alertView.secondTextField.keyboardAppearance = UIKeyboardAppearanceDefault;
        [self.postDetailViewController.view addSubview:alertView];
    }
    
    [UIView animateWithDuration:0.2 animations:^{
        alertView.alpha = 1.0;
    }];

    self.customSizeAlert = alertView;
}


- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
	if (alertView.tag == 101) { //VideoPress Promo Alert
		switch (buttonIndex) {
			case 0:
				break;
			case 1:
			{
				NSString *buttonTitle = [alertView buttonTitleAtIndex:buttonIndex];
				if ([buttonTitle isEqualToString:NSLocalizedString(@"Yes", @"")]){
					[[UIApplication sharedApplication] openURL:[NSURL URLWithString: @"http://videopress.com"]];
				}
			}		
			default:
				break;
		}
	}

    if (currentAlert == alertView) {
        currentAlert = nil;
    }
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (currentAlert == alertView) {
        currentAlert = nil;
    }

	if (alertView.tag == 101) { //VideoPress Promo Alert
	
		return;
	}
}

- (void)imagePickerController:(UIImagePickerController *)thePicker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    // On iOS7 Beta 6 the image picker seems to override our preferred setting so we force the status bar color back.
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];

	if([[info valueForKey:@"UIImagePickerControllerMediaType"] isEqualToString:@"public.movie"]) {
		self.currentVideo = [info mutableCopy];
		if(self.didChangeOrientationDuringRecord == YES)
			[self showOrientationChangedActionSheet];
		else if(self.isLibraryMedia == NO)
			[self processRecordedVideo];
		else
			[self performSelectorOnMainThread:@selector(processLibraryVideo) withObject:nil waitUntilDone:NO];
	}
	else if([[info valueForKey:@"UIImagePickerControllerMediaType"] isEqualToString:@"public.image"]) {
		UIImage *image = [info valueForKey:@"UIImagePickerControllerOriginalImage"];
		if (thePicker.sourceType == UIImagePickerControllerSourceTypeCamera)
			UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
		currentImage = image;
		
		//UIImagePickerControllerReferenceURL = "assets-library://asset/asset.JPG?id=1000000050&ext=JPG").
        NSURL *assetURL = nil;
        if (&UIImagePickerControllerReferenceURL != NULL) {
            assetURL = [info objectForKey:UIImagePickerControllerReferenceURL];
        }
        if (assetURL) {
            [self getMetadataFromAssetForURL:assetURL];
        } else {
            NSDictionary *metadata = nil;
            if (&UIImagePickerControllerMediaMetadata != NULL) {
                metadata = [info objectForKey:UIImagePickerControllerMediaMetadata];
            }
            if (metadata) {
                NSMutableDictionary *mutableMetadata = [metadata mutableCopy];
                NSDictionary *gpsData = [mutableMetadata objectForKey:@"{GPS}"];
                if (!gpsData && self.post.geolocation) {
                    /*
                     Sample GPS data dictionary
                     "{GPS}" =     {
                     Altitude = 188;
                     AltitudeRef = 0;
                     ImgDirection = "84.19556";
                     ImgDirectionRef = T;
                     Latitude = "41.01333333333333";
                     LatitudeRef = N;
                     Longitude = "0.01666666666666";
                     LongitudeRef = W;
                     TimeStamp = "10:34:04.00";
                     };
                     */
                    CLLocationDegrees latitude = self.post.geolocation.latitude;
                    CLLocationDegrees longitude = self.post.geolocation.longitude;
                    NSDictionary *gps = [NSDictionary dictionaryWithObjectsAndKeys:
                                         [NSNumber numberWithDouble:fabs(latitude)], @"Latitude",
                                         (latitude < 0.0) ? @"S" : @"N", @"LatitudeRef",
                                         [NSNumber numberWithDouble:fabs(longitude)], @"Longitude",
                                         (longitude < 0.0) ? @"W" : @"E", @"LongitudeRef",
                                         nil];
                    [mutableMetadata setObject:gps forKey:@"{GPS}"];
                }
                [mutableMetadata removeObjectForKey:@"Orientation"];
                [mutableMetadata removeObjectForKey:@"{TIFF}"];
                self.currentImageMetadata = mutableMetadata;
            }
        }
		
		NSNumberFormatter *nf = [[NSNumberFormatter alloc] init];
		[nf setNumberStyle:NSNumberFormatterDecimalStyle];
		NSNumber *resizePreference = [NSNumber numberWithInt:-1];
		if([[NSUserDefaults standardUserDefaults] objectForKey:@"media_resize_preference"] != nil)
			resizePreference = [nf numberFromString:[[NSUserDefaults standardUserDefaults] objectForKey:@"media_resize_preference"]];
		BOOL showResizeActionSheet;
		switch ([resizePreference intValue]) {
			case 0:
            {
                showResizeActionSheet = true;
				break;
            }
			case 1:
            {
				[self useImage:[self resizeImage:currentImage toSize:kResizeSmall]];
				break;
            }
			case 2:
            {
				[self useImage:[self resizeImage:currentImage toSize:kResizeMedium]];
				break;
            }
			case 3:
            {
				[self useImage:[self resizeImage:currentImage toSize:kResizeLarge]];
				break;
            }
			case 4:
            {
				//[self useImage:currentImage];
                [self useImage:[self resizeImage:currentImage toSize:kResizeOriginal]];
				break;
            }
			default:
            {
                showResizeActionSheet = true;
				break;
            }
		}
		
        if (addPopover != nil) {
            [addPopover dismissPopoverAnimated:YES];
            [[CPopoverManager instance] setCurrentPopoverController:NULL];
            addPopover = nil;
            [self showResizeActionSheet];
        } else {
            [postDetailViewController.navigationController dismissViewControllerAnimated:YES completion:^{
                if (showResizeActionSheet) {
                    [self showResizeActionSheet];
                }
            }];
        }
	}

	if(IS_IPAD){
		[addPopover dismissPopoverAnimated:YES];
		[[CPopoverManager instance] setCurrentPopoverController:NULL];
		addPopover = nil;
	}
}


/* 
 * Take Asset URL and set imageJPEG property to NSData containing the
 * associated JPEG, including the metadata we're after.
 */
-(void)getMetadataFromAssetForURL:(NSURL *)url {	
    ALAssetsLibrary* assetslibrary = [[ALAssetsLibrary alloc] init];
    [assetslibrary assetForURL:url
				   resultBlock: ^(ALAsset *myasset) {
					   ALAssetRepresentation *rep = [myasset defaultRepresentation];
					   
					   WPLog(@"getJPEGFromAssetForURL: default asset representation for %@: uti: %@ size: %lld url: %@ orientation: %d scale: %f metadata: %@", 
							 url, [rep UTI], [rep size], [rep url], [rep orientation], 
							 [rep scale], [rep metadata]);
					   
					   Byte *buf = malloc([rep size]);  // will be freed automatically when associated NSData is deallocated
					   NSError *err = nil;
					   NSUInteger bytes = [rep getBytes:buf fromOffset:0LL 
												 length:[rep size] error:&err];
					   if (err || bytes == 0) {
						   // Are err and bytes == 0 redundant? Doc says 0 return means 
						   // error occurred which presumably means NSError is returned.
						   free(buf); // Free up memory so we don't leak.
						   WPLog(@"error from getBytes: %@", err);
						   
						   return;
					   } 
					   NSData *imageJPEG = [NSData dataWithBytesNoCopy:buf length:[rep size] 
														  freeWhenDone:YES];  // YES means free malloc'ed buf that backs this when deallocated
					   
					   CGImageSourceRef  source ;
					   source = CGImageSourceCreateWithData((__bridge CFDataRef)imageJPEG, NULL);
					   
                       NSDictionary *metadata = (NSDictionary *) CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,0,NULL));
                       
                       //make the metadata dictionary mutable so we can remove properties to it
                       NSMutableDictionary *metadataAsMutable = [metadata mutableCopy];

					   if(!self.apost.blog.geolocationEnabled) {
						   //we should remove the GPS info if the blog has the geolocation set to off
						   
						   //get all the metadata in the image
						   [metadataAsMutable removeObjectForKey:@"{GPS}"];
					   }
                       [metadataAsMutable removeObjectForKey:@"Orientation"];
                       [metadataAsMutable removeObjectForKey:@"{TIFF}"];
                       self.currentImageMetadata = [NSDictionary dictionaryWithDictionary:metadataAsMutable];
					   
					   CFRelease(source);
				   }
				  failureBlock: ^(NSError *err) {
					  WPLog(@"can't get asset %@: %@", url, err);
					  self.currentImageMetadata = nil;
				  }];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    // On iOS7 Beta 6 the image picker seems to override our preferred setting so we force the status bar color back.
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleLightContent];

    [postDetailViewController.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)processRecordedVideo {
    [postDetailViewController.navigationController dismissViewControllerAnimated:YES completion:nil];

	[self.currentVideo setValue:[NSNumber numberWithInt:currentOrientation] forKey:@"orientation"];
	NSString *tempVideoPath = [(NSURL *)[currentVideo valueForKey:UIImagePickerControllerMediaURL] absoluteString];
    tempVideoPath = [self videoPathFromVideoUrl:tempVideoPath];
	if (UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(tempVideoPath)) {
		UISaveVideoAtPathToSavedPhotosAlbum(tempVideoPath, self, @selector(video:didFinishSavingWithError:contextInfo:), nil);
	}
}

- (void)processLibraryVideo {
	NSURL *videoURL = [currentVideo valueForKey:UIImagePickerControllerMediaURL];
	if(videoURL == nil)
		videoURL = [currentVideo valueForKey:UIImagePickerControllerReferenceURL];
	
	if(videoURL != nil) {
		if(IS_IPAD == YES)
			[addPopover dismissPopoverAnimated:YES];
		else {
            [postDetailViewController.navigationController dismissViewControllerAnimated:YES completion:nil];
		}
		
		[self.currentVideo setValue:[NSNumber numberWithInt:currentOrientation] forKey:@"orientation"];
		
		[self useVideo:[self videoPathFromVideoUrl:[videoURL absoluteString]]];
		self.currentVideo = nil;
		self.isLibraryMedia = NO;
	}
}

- (void)video:(NSString *)videoPath didFinishSavingWithError:(NSError *)error contextInfo:(NSString *)contextInfo {
	[self useVideo:videoPath];
	currentVideo = nil;
}

- (UIImage *)fixImageOrientation:(UIImage *)img {
    CGSize size = [img size];
	
    UIImageOrientation imageOrientation = [img imageOrientation];
	
    if (imageOrientation == UIImageOrientationUp)
        return img;
	
    CGImageRef imageRef = [img CGImage];
    CGContextRef bitmap = CGBitmapContextCreate(
												NULL,
												size.width,
												size.height,
												CGImageGetBitsPerComponent(imageRef),
												4 * size.width,
												CGImageGetColorSpace(imageRef),
												CGImageGetBitmapInfo(imageRef));
	
    CGContextTranslateCTM(bitmap, size.width, size.height);
	
    switch (imageOrientation) {
        case UIImageOrientationDown:
            // rotate 180 degees CCW
            CGContextRotateCTM(bitmap, radians(180.));
            break;
        case UIImageOrientationLeft:
            // rotate 90 degrees CW
            CGContextRotateCTM(bitmap, radians(-90.));
            break;
        case UIImageOrientationRight:
            // rotate 90 degrees5 CCW
            CGContextRotateCTM(bitmap, radians(90.));
            break;
        default:
            break;
    }
	
    CGContextDrawImage(bitmap, CGRectMake(0, 0, size.width, size.height), imageRef);
	
    CGImageRef ref = CGBitmapContextCreateImage(bitmap);
    CGContextRelease(bitmap);
    UIImage *oimg = [UIImage imageWithCGImage:ref];
    CGImageRelease(ref);
	
    return oimg;
}

- (UIImage *)resizeImage:(UIImage *)original toSize:(MediaResize)resize {
    NSDictionary* predefDim = [self.apost.blog getImageResizeDimensions];
    CGSize smallSize =  [[predefDim objectForKey: @"smallSize"] CGSizeValue];
    CGSize mediumSize = [[predefDim objectForKey: @"mediumSize"] CGSizeValue];
    CGSize largeSize =  [[predefDim objectForKey: @"largeSize"] CGSizeValue];
    switch (currentImage.imageOrientation) { 
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            smallSize = CGSizeMake(smallSize.height, smallSize.width);
            mediumSize = CGSizeMake(mediumSize.height, mediumSize.width);
            largeSize = CGSizeMake(largeSize.height, largeSize.width);
            break;
        default:
            break;
    }
    
    CGSize originalSize = CGSizeMake(currentImage.size.width, currentImage.size.height); //The dimensions of the image, taking orientation into account.
	
	// Resize the image using the selected dimensions
	UIImage *resizedImage = original;
	switch (resize) {
		case kResizeSmall:
			if(currentImage.size.width > smallSize.width  || currentImage.size.height > smallSize.height)
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:smallSize  
												interpolationQuality:kCGInterpolationHigh]; 
			else  
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:originalSize  
												interpolationQuality:kCGInterpolationHigh];
			break;
		case kResizeMedium:
			if(currentImage.size.width > mediumSize.width  || currentImage.size.height > mediumSize.height) 
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:mediumSize  
												interpolationQuality:kCGInterpolationHigh]; 
			else  
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:originalSize  
												interpolationQuality:kCGInterpolationHigh];
			break;
		case kResizeLarge:
			if(currentImage.size.width > largeSize.width || currentImage.size.height > largeSize.height) 
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:largeSize  
												interpolationQuality:kCGInterpolationHigh]; 
			else  
				resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit  
															  bounds:originalSize  
												interpolationQuality:kCGInterpolationHigh];
			break;
		case kResizeOriginal:
			resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit 
														  bounds:originalSize 
											interpolationQuality:kCGInterpolationHigh];
			break;
	}

	
	return resizedImage;
}

/* Used in Custom Dimensions Resize */
- (UIImage *)resizeImage:(UIImage *)original width:(CGFloat)width height:(CGFloat)height {
	UIImage *resizedImage = original;
	if(currentImage.size.width > width || currentImage.size.height > height) {
		// Resize the image using the selected dimensions
		resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit
													  bounds:CGSizeMake(width, height) 
										interpolationQuality:kCGInterpolationHigh];
	} else {
		//use the original dimension
		resizedImage = [original resizedImageWithContentMode:UIViewContentModeScaleAspectFit 
													  bounds:CGSizeMake(currentImage.size.width, currentImage.size.height) 
										interpolationQuality:kCGInterpolationHigh];
	}
	
	return resizedImage;
}

- (UIImage *)generateThumbnailFromImage:(UIImage *)theImage andSize:(CGSize)targetSize {
    return [theImage thumbnailImage:75 transparentBorder:0 cornerRadius:0 interpolationQuality:kCGInterpolationHigh]; 
}

- (void)useImage:(UIImage *)theImage {
	Media *imageMedia = [Media newMediaForPost:self.apost];
	NSData *imageData = UIImageJPEGRepresentation(theImage, 0.90);
	UIImage *imageThumbnail = [self generateThumbnailFromImage:theImage andSize:CGSizeMake(75, 75)];
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyyMMdd-HHmmss"];
		
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	NSString *filename = [NSString stringWithFormat:@"%@.jpg", [formatter stringFromDate:[NSDate date]]];
	NSString *filepath = [documentsDirectory stringByAppendingPathComponent:filename];

	if (self.currentImageMetadata != nil) {
		// Write the EXIF data with the image data to disk
		CGImageSourceRef  source = NULL;
        CGImageDestinationRef destination = NULL;
		BOOL success = NO;
        //this will be the data CGImageDestinationRef will write into
        NSMutableData *dest_data = [NSMutableData data];

		source = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
        if (source) {
            CFStringRef UTI = CGImageSourceGetType(source); //this is the type of image (e.g., public.jpeg)
            destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)dest_data,UTI,1,NULL);
            
            if(destination) {                
                //add the image contained in the image source to the destination, copying the old metadata
                CGImageDestinationAddImageFromSource(destination,source,0, (__bridge CFDictionaryRef) self.currentImageMetadata);
                
                //tell the destination to write the image data and metadata into our data object.
                //It will return false if something goes wrong
                success = CGImageDestinationFinalize(destination);
            } else {
                WPFLog(@"***Could not create image destination ***");
            }
        } else {
            WPFLog(@"***Could not create image source ***");
        }
		
		if(!success) {
			WPLog(@"***Could not create data from image destination ***");
			//write the data without EXIF to disk
			NSFileManager *fileManager = [NSFileManager defaultManager];
			[fileManager createFileAtPath:filepath contents:imageData attributes:nil];
		} else {
			//write it to disk
			[dest_data writeToFile:filepath atomically:YES];
		}
		//cleanup
        if (destination)
            CFRelease(destination);
        if (source)
            CFRelease(source);
    } else {
		NSFileManager *fileManager = [NSFileManager defaultManager];
		[fileManager createFileAtPath:filepath contents:imageData attributes:nil];
	}

	if(currentOrientation == kLandscape)
		imageMedia.orientation = @"landscape";
	else
		imageMedia.orientation = @"portrait";
	imageMedia.creationDate = [NSDate date];
	imageMedia.filename = filename;
	imageMedia.localURL = filepath;
	imageMedia.filesize = [NSNumber numberWithInt:(imageData.length/1024)];
    if (isPickingFeaturedImage)
        imageMedia.mediaType = @"featured";
    else
        imageMedia.mediaType = @"image";
	imageMedia.thumbnail = UIImageJPEGRepresentation(imageThumbnail, 0.90);
	imageMedia.width = [NSNumber numberWithInt:theImage.size.width];
	imageMedia.height = [NSNumber numberWithInt:theImage.size.height];
    if (isPickingFeaturedImage)
        [[NSNotificationCenter defaultCenter] postNotificationName:@"UploadingFeaturedImage" object:nil];

    [imageMedia uploadWithSuccess:^{
        if ([imageMedia isDeleted]) {
            NSLog(@"Media deleted while uploading (%@)", imageMedia);
            return;
        }
        if (!isPickingFeaturedImage) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldInsertMediaBelow" object:imageMedia];
        }
        else {
            
        }
        [imageMedia save];
    } failure:^(NSError *error) {
        if (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) {
            return;
        }

        [WPError showAlertWithError:error title:NSLocalizedString(@"Upload failed", @"")];
    }];
	
	isAddingMedia = NO;
	
    if (!IS_IOS7) {
        if (isPickingFeaturedImage)
            [postDetailViewController switchToSettings];
        else
            [postDetailViewController switchToMedia];
    }
}

- (void)useVideo:(NSString *)videoURL {
	BOOL copySuccess = FALSE;
	Media *videoMedia;
	NSDictionary *attributes;
    UIImage *thumbnail = nil;
	NSTimeInterval duration = 0.0;
    NSURL *contentURL = [NSURL fileURLWithPath:videoURL];

    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:contentURL
                                                 options:[NSDictionary dictionaryWithObjectsAndKeys:
                                                          [NSNumber numberWithBool:YES], AVURLAssetPreferPreciseDurationAndTimingKey,
                                                          nil]];
    if (asset) {
        duration = CMTimeGetSeconds(asset.duration);
        AVAssetImageGenerator *imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        imageGenerator.appliesPreferredTrackTransform = YES;

        CMTime midpoint = CMTimeMakeWithSeconds(duration/2.0, 600);
        NSError *error = nil;
        CMTime actualTime;
        CGImageRef halfWayImage = [imageGenerator copyCGImageAtTime:midpoint actualTime:&actualTime error:&error];

        if (halfWayImage != NULL) {
            thumbnail = [UIImage imageWithCGImage:halfWayImage];
            // Do something interesting with the image.
            CGImageRelease(halfWayImage);
        }
    }

	UIImage *videoThumbnail = [self generateThumbnailFromImage:thumbnail andSize:CGSizeMake(75, 75)];
	
	// Save to local file
	NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
	[formatter setDateFormat:@"yyyyMMdd-HHmmss"];	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths objectAtIndex:0];
	NSString *filename = [NSString stringWithFormat:@"%@.mov", [formatter stringFromDate:[NSDate date]]];
	NSString *filepath = [documentsDirectory stringByAppendingPathComponent:filename];
	
	if(videoURL != nil) {
		// Copy the video from temp to blog directory
		NSError *error = nil;
		if ((attributes = [fileManager attributesOfItemAtPath:videoURL error:nil]) != nil) {
			if([fileManager isReadableFileAtPath:videoURL] == YES)
				copySuccess = [fileManager copyItemAtPath:videoURL toPath:filepath error:&error];
		}
	}
	
	if(copySuccess == YES) {
		videoMedia = [Media newMediaForPost:self.apost];
		
		if(currentOrientation == kLandscape)
			videoMedia.orientation = @"landscape";
		else
			videoMedia.orientation = @"portrait";
		videoMedia.creationDate = [NSDate date];
		[videoMedia setFilename:filename];
		[videoMedia setLocalURL:filepath];
		
		videoMedia.filesize = [NSNumber numberWithInt:([[attributes objectForKey: NSFileSize] intValue]/1024)];
		videoMedia.mediaType = @"video";
		videoMedia.thumbnail = UIImageJPEGRepresentation(videoThumbnail, 1.0);
		videoMedia.length = [NSNumber numberWithFloat:duration];
		CGImageRef cgVideoThumbnail = thumbnail.CGImage;
		NSUInteger videoWidth = CGImageGetWidth(cgVideoThumbnail);
		NSUInteger videoHeight = CGImageGetHeight(cgVideoThumbnail);
		videoMedia.width = [NSNumber numberWithInt:videoWidth];
		videoMedia.height = [NSNumber numberWithInt:videoHeight];

		[videoMedia uploadWithSuccess:^{
            if ([videoMedia isDeleted]) {
                NSLog(@"Media deleted while uploading (%@)", videoMedia);
                return;
            }
            [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldInsertMediaBelow" object:videoMedia];
            [videoMedia save];
        } failure:^(NSError *error) {
            [WPError showAlertWithError:error title:NSLocalizedString(@"Upload failed", @"")];
        }];
		isAddingMedia = NO;
		
        if (!IS_IOS7) {
            //switch to the attachment view if we're not already there
            [postDetailViewController switchToMedia];            
        }
	}
	else {
        if (currentAlert == nil) {
            UIAlertView *videoAlert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error Copying Video", @"")
                                                                 message:NSLocalizedString(@"There was an error copying the video for upload. Please try again.", @"")
                                                                delegate:self
                                                       cancelButtonTitle:NSLocalizedString(@"OK", @"")
                                                       otherButtonTitles:nil];
            [videoAlert show];
            currentAlert = videoAlert;
        }
	}
}

- (BOOL)isDeviceSupportVideo {
	if(([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera] == YES) && 
	   ([[UIImagePickerController availableMediaTypesForSourceType:UIImagePickerControllerSourceTypeCamera] containsObject:(NSString *)kUTTypeMovie]))
		return YES;
	else
		return NO;
}

- (BOOL)isDeviceSupportVideoAndVideoPressEnabled{
	if([self isDeviceSupportVideo] && (self.videoEnabled == YES))
		return YES;
	else
		return NO;
}

- (void)mediaDidUploadSuccessfully:(NSNotification *)notification {
    Media *media = (Media *)[notification object];
    if ((media == nil) || ([media isDeleted])) {
        NSLog(@"Media deleted while uploading (%@)", media);
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ShouldInsertMediaBelow" object:media];
    [media save];
	self.isAddingMedia = NO;
}

- (void)mediaUploadFailed:(NSNotification *)notification {
	self.isAddingMedia = NO;
}

- (void)deviceDidRotate:(NSNotification *)notification {
	if(isAddingMedia == YES) {
		if(self.currentOrientation != [self interpretOrientation:[[UIDevice currentDevice] orientation]]) {		
			self.currentOrientation = [self interpretOrientation:[[UIDevice currentDevice] orientation]];
			didChangeOrientationDuringRecord = YES;
		}
	}
}

- (void)checkVideoPressEnabled {
    if(self.isCheckingVideoCapability)
        return;

    self.isCheckingVideoCapability = YES;
    [self.apost.blog checkVideoPressEnabledWithSuccess:^(BOOL enabled) {
        self.videoEnabled = enabled;
        self.isCheckingVideoCapability = NO;
    } failure:^(NSError *error) {
        WPLog(@"checkVideoPressEnabled failed: %@", [error localizedDescription]);
        self.videoEnabled = YES;
        self.isCheckingVideoCapability = NO;
    }];
}

#pragma mark -
#pragma mark Results Controller

- (NSFetchedResultsController *)resultsController {
    if (resultsController != nil) {
        return resultsController;
    }
    
    WordPressAppDelegate *appDelegate = (WordPressAppDelegate*)[[UIApplication sharedApplication] delegate];
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    [fetchRequest setEntity:[NSEntityDescription entityForName:@"Media" inManagedObjectContext:appDelegate.managedObjectContext]];
    [fetchRequest setPredicate:[NSPredicate predicateWithFormat:@"%@ IN posts AND mediaType != 'featured'", self.apost]];
    NSSortDescriptor *sortDescriptorDate = [[NSSortDescriptor alloc] initWithKey:@"creationDate" ascending:NO];
    NSArray *sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptorDate, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    resultsController = [[NSFetchedResultsController alloc]
                                                      initWithFetchRequest:fetchRequest
                                                      managedObjectContext:appDelegate.managedObjectContext
                                                      sectionNameKeyPath:nil
                                                      cacheName:[NSString stringWithFormat:@"Media-%@-%@",
                                                                 self.apost.blog.hostURL,
                                                                 self.apost.postID]];
    resultsController.delegate = self;
    
     sortDescriptorDate = nil;
     sortDescriptors = nil;
    
    NSError *error = nil;
    if (![resultsController performFetch:&error]) {
        NSLog(@"Couldn't fetch media");
        resultsController = nil;
    }
    
    return resultsController;
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {
    
    if (type != NSFetchedResultsChangeUpdate) {
        // For anything that is not an update just reload the table.
        [table reloadData];
        return;
    }
    
    // For updates, update the cell w/o refreshing the whole tableview.
    UITableViewCell *cell = [self.table cellForRowAtIndexPath:indexPath];
    if (cell) {
        [self configureCell:cell atIndexPath:indexPath];
    }

}

- (NSString *)videoPathFromVideoUrl:(NSString *)videoUrl
{
    // Determine the video's library path.
    // In iOS 6 this returns as file://localhost/private/var/mobile/Applications/73DCDAD0-397C-404D-9456-4C5A360ABE0D/tmp//trim.lmhYmN.MOV
    // In iOS 7 this returns as file:///private/var/mobile/Applications/9946F4C5-5B16-4EA5-850C-DDA701A47E61/tmp/trim.4F72621B-04AE-47F2-A551-068F62E8D16F.MOV

    NSError *error;
    NSRegularExpression *regEx = [NSRegularExpression regularExpressionWithPattern:@"(/var.*$)" options:NSRegularExpressionCaseInsensitive error:&error];
    NSString *videoPath = videoUrl;
    NSArray *matches = [regEx matchesInString:videoUrl options:0 range:NSMakeRange(0, [videoUrl length])];
    for (NSTextCheckingResult *result in matches) {
        if ([result numberOfRanges] < 2)
            continue;
        NSRange videoUrlRange = [result rangeAtIndex:1];
        videoPath = [videoUrl substringWithRange:videoUrlRange];
    }
    
    return videoPath;
}

- (NSString *)formattedStatEventString:(NSString *)event
{
    return [NSString stringWithFormat:@"%@ - %@", self.statsPrefix, event];
}

@end
