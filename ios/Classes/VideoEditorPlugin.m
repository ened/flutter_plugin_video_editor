#import "VideoEditorPlugin.h"
#import <video_editor/video_editor-Swift.h>

@implementation VideoEditorPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftVideoEditorPlugin registerWithRegistrar:registrar];
}
@end
