import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:async';

import 'package:media_info/media_info.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_editor/video_editor.dart';

import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(MyApp());

const _kPrefLastFileName = 'last_path';
const _kPrefShowPerformanceOverlay = 'show_performance_overlay';

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map<String, dynamic> _resolution;
  String _file;

  bool _showPerformanceOverlay = false;

  VideoEditor _editor = VideoEditor();

  @override
  void initState() {
    super.initState();

    PermissionHandler().requestPermissions([PermissionGroup.storage]);

    SharedPreferences.getInstance().then((pref) {
      final String path = pref.getString(_kPrefLastFileName);
      if (path?.isNotEmpty == true && mounted) {
        if (Platform.isIOS) {
          getApplicationDocumentsDirectory().then((d) {
            _loadFile('${d.path}/$path');
          });
        } else {
          _loadFile(path);
        }
      }

      final bool spo = pref.getBool(_kPrefShowPerformanceOverlay);
      if (spo != null && spo != _showPerformanceOverlay && mounted) {
        setState(() {
          _showPerformanceOverlay = spo;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      showPerformanceOverlay: _showPerformanceOverlay,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Video Editor Example'),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.drive_eta),
              onPressed: () {
                final bool newValue = !_showPerformanceOverlay;
                SharedPreferences.getInstance().then((p) {
                  p.setBool(_kPrefShowPerformanceOverlay, newValue);
                });
                setState(() {
                  _showPerformanceOverlay = newValue;
                });
              },
            ),
          ],
        ),
        body: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              RaisedButton(
                child: Text('Select & Analyse'),
                onPressed: _handleAnalyze,
              ),
              if (_file != null) ...[
                SizedBox(height: 16),
                Text(_file, style: Theme.of(context).textTheme.caption),
              ],
              if (_resolution != null) ...[
                SizedBox(height: 16),
                Text(
                    '${_resolution['width']}X${_resolution['height']}@${_resolution['frameRate']} FPS\n'),
                Text(
                    'Duration: ${Duration(milliseconds: _resolution['durationMs'])}\n'),
              ],
              ..._editActions(),
            ],
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _editActions() {
    if (_file == null || _resolution == null) {
      return [];
    }

    final Duration d = Duration(milliseconds: _resolution['durationMs']);
    if (d.inSeconds < 2) {
      return [Text('Video length too short')];
    }

    final mid = Duration(milliseconds: (d.inMilliseconds ~/ 2));

    return [
      Text('Cut', style: Theme.of(context).textTheme.body2),
      RaisedButton(
        child: Text('START - $mid'),
        onPressed: () async {
          _handleCut(0, mid.inMilliseconds);
        },
      ),
      RaisedButton(
        child: Text('$mid - END'),
        onPressed: () {
          _handleCut(mid.inMilliseconds, d.inMilliseconds);
        },
      ),
      SizedBox(height: 16),
      StreamBuilder<VideoTrimProgress>(
        stream: _editor.observeTrimProgress(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return SizedBox();
          }

          if (snapshot.hasError) {
            return Text('${snapshot.error}');
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: snapshot.data.progress),
              if (snapshot.data.progress > 0.0 &&
                  snapshot.data.progress != 1.0 &&
                  snapshot.data.error == null)
                Row(
                  children: <Widget>[
                    Spacer(),
                    FlatButton(
                      child: Text('Cancel'),
                      onPressed: () {
                        _editor.cancelTrim();
                      },
                    ),
                  ],
                ),
              if (snapshot.data.progress == 1.0 &&
                  snapshot.data.error == null) ...[
                SizedBox(height: 8),
                Builder(builder: (context) {
                  print('Output: ${snapshot.data.output}');
                  return Text('Output: ${snapshot.data.output}');
                }),
              ],
            ],
          );
        },
      ),
    ];
  }

  void _handleAnalyze() async {
    final file = await FilePicker.getFile(type: FileType.ANY);

    if (file == null) {
      return;
    }

    _loadFile(file.path);
  }

  void _handleCut(int startMs, int endMs) async {
    final tmpDir = Platform.isIOS
        ? await getApplicationDocumentsDirectory()
        : await getExternalStorageDirectory();
    final output = '${tmpDir.path}/video-output.mp4';

    try {
      File(output).deleteSync();
    } catch (e) {
      //
    }

    try {
      await _editor.trimVideo(
        _file,
        output,
        VideoEditorOptions(startMs, endMs),
      );
    } on VideoEditorError catch (e) {
      print('can not start video edit operation: $e');
    }
  }

  Future<void> _loadFile(String path) async {
    print('Path: $path');
    final preferences = await SharedPreferences.getInstance();
    
    if (Platform.isIOS) {
      preferences.setString(_kPrefLastFileName, path.split('/').last);
    } else {
      preferences.setString(_kPrefLastFileName, path);
    }

    final info = await MediaInfo().getMediaInfo(path);

    if (info.isEmpty) {
      SharedPreferences.getInstance().then((p) {
        p.clear();
      });
      return;
    }

    print('details: $info');

    setState(() {
      _file = path;
      _resolution = info;
    });
  }
}
