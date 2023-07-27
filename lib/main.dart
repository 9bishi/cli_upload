import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';

void main() {
  runApp(VideoUploadApp());
}

class VideoUploadApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '视频上传',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: VideoUploadHomePage(),
    );
  }
}

class VideoUploadHomePage extends StatefulWidget {
  @override
  _VideoUploadHomePageState createState() => _VideoUploadHomePageState();
}

class _VideoUploadHomePageState extends State<VideoUploadHomePage> {
  List<File> _selectedVideos = [];
  List<double> _uploadProgressList = [];
  List<bool> _uploadingList = [];
  List<String> _uploadStatusList = [];
  List<String?> _videoUrlList = [];
  List<List<String>> _uploadRecordsList = [];
  List<File> _uploadQueue = []; // 上传队列
  bool _isConcurrentUpload = true; // 默认为并发上传

  void _selectVideos() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp4', 'avi', 'mov'],
    );

    if (result != null) {
      List<File> files = result.paths.map((path) => File(path!)).toList();
      setState(() {
        _selectedVideos = files;
        _uploadProgressList = List<double>.filled(files.length, 0.0);
        _uploadingList = List<bool>.filled(files.length, false);
        _uploadStatusList = List<String>.filled(files.length, '');
        _videoUrlList = List<String?>.filled(files.length, null);
        _uploadRecordsList = List<List<String>>.filled(files.length, []);
      });
    }
  }

  Future<void> _uploadVideos() async {
    // 将选中的视频文件加入上传队列
    _uploadQueue.clear();
    _uploadQueue.addAll(_selectedVideos);

    if (_isConcurrentUpload) {
      // 并发上传
      await _concurrentUpload();
    } else {
      // 顺序上传
      await _sequentialUpload();
    }
  }

  // 并发上传
  Future<void> _concurrentUpload() async {
    await Future.wait(_uploadQueue.map((videoFile) async {
      int index = _selectedVideos.indexOf(videoFile);
      await _compressAndUploadVideo(index);
    }));
  }

  // 顺序上传
  Future<void> _sequentialUpload() async {
    for (int i = 0; i < _uploadQueue.length; i++) {
      int index = _selectedVideos.indexOf(_uploadQueue[i]);
      await _compressAndUploadVideo(index);
    }
  }

  Future<void> _compressAndUploadVideo(int index) async {
    File selectedVideo = _selectedVideos[index];

    // 获取应用的缓存目录
    Directory cacheDir = await getTemporaryDirectory();
    String tempVideoPath = path.join(cacheDir.path, 'temp_video.mp4');

    setState(() {
      _uploadingList[index] = true;
      _uploadStatusList[index] = '视频压缩中...';
    });

    // 使用flutter_ffmpeg压缩视频
    final FlutterFFmpeg _flutterFFmpeg = FlutterFFmpeg();
    int rc = await _flutterFFmpeg.execute(
        '-i ${selectedVideo.path} -b:v 1M $tempVideoPath');

    if (rc != 0) {
      // 压缩失败
      setState(() {
        _uploadingList[index] = false;
        _uploadStatusList[index] = '压缩失败';
      });
      return;
    }

    // 压缩成功，开始上传压缩后的视频
    setState(() {
      _uploadProgressList[index] = 0.0;
      _uploadStatusList[index] = '上传中...';
    });

    String apiUrl = 'https://cdn.cli.plus/api.php';

    FormData formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        tempVideoPath,
        filename: path.basename(tempVideoPath),
      ),
      'format': 'json',
      'show': 1,
    });

    Dio dio = Dio();
    dio.interceptors.add(LogInterceptor()); // 添加日志拦截器，可查看请求日志

    try {
      Response response = await dio.post(
        apiUrl,
        data: formData,
        onSendProgress: (sent, total) {
          double progress = sent / total;
          setState(() {
            _uploadProgressList[index] = progress;
          });
        },
        options: Options(
          method: 'POST',
          headers: {
            'Content-Range': 'bytes */${selectedVideo.lengthSync()}',
            'Content-Disposition': 'attachment; filename=${selectedVideo.path.split('/').last}',
          },
        ),
      );

      if (response.statusCode == 200) {
        // 处理成功响应
        Map<String, dynamic> data = response.data;
        int code = data['code'];
        String msg = data['msg'];
        String videoUrl = data['downurl'];
        // 获取其他返回参数并根据需求使用
        // ...

        List<String> uploadRecords = _uploadRecordsList[index];
        uploadRecords.add(DateTime.now().toString());

        setState(() {
          _uploadingList[index] = false;
          _uploadStatusList[index] = '上传完成！';
          _videoUrlList[index] = videoUrl;
          _uploadRecordsList[index] = uploadRecords;
        });
      } else {
        // 处理错误响应
        setState(() {
          _uploadingList[index] = false;
          _uploadStatusList[index] = '上传失败';
        });
        return;
      }
    } catch (error) {
      // 处理网络请求错误
      setState(() {
        _uploadingList[index] = false;
        _uploadStatusList[index] = '上传失败';
      });
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('视频上传'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton(
              onPressed: _selectVideos,
              child: Text('选择视频'),
            ),
            SizedBox(height: 20.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text('上传方式：'),
                SizedBox(width: 10.0),
                DropdownButton<bool>(
                  value: _isConcurrentUpload,
                  onChanged: (value) {
                    setState(() {
                      _isConcurrentUpload = value!;
                    });
                  },
                  items: <DropdownMenuItem<bool>>[
                    DropdownMenuItem<bool>(
                      value: true,
                      child: Text('并发上传'),
                    ),
                    DropdownMenuItem<bool>(
                      value: false,
                      child: Text('顺序上传'),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20.0),
            ElevatedButton(
              onPressed: _uploadVideos,
              child: Text('上传视频'),
            ),
            SizedBox(height: 20.0),
            Expanded(
              child: ListView.builder(
                itemCount: _selectedVideos.length,
                itemBuilder: (BuildContext context, int index) {
                  return VideoUploadWidget(
                    file: _selectedVideos[index],
                    uploadProgress: _uploadProgressList[index],
                    uploading: _uploadingList[index],
                    uploadStatus: _uploadStatusList[index],
                    videoUrl: _videoUrlList[index],
                    uploadRecords: _uploadRecordsList[index],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VideoUploadWidget extends StatelessWidget {
  final File file;
  final double uploadProgress;
  final bool uploading;
  final String uploadStatus;
  final String? videoUrl;
  final List<String> uploadRecords;

  const VideoUploadWidget({
    Key? key,
    required this.file,
    required this.uploadProgress,
    required this.uploading,
    required this.uploadStatus,
    required this.videoUrl,
    required this.uploadRecords,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (file != null)
              Container(
                height: 200,
                child: VideoPlayerWidget(file: file),
              ),
            SizedBox(height: 20.0),
            if (uploading)
              LinearProgressIndicator(value: uploadProgress),
            SizedBox(height: 10.0),
            Text(uploadStatus),
            SizedBox(height: 10.0),
            if (videoUrl != null)
              Text('视频网址: $videoUrl'),
            SizedBox(height: 10.0),
            Text('上传记录:'),
            Column(
              children: uploadRecords.map((record) => Text(record)).toList(),
            ),
            SizedBox(height: 20.0),
          ],
        ),
      ),
    );
  }
}

class VideoPlayerWidget extends StatefulWidget {
  final File file;

  const VideoPlayerWidget({Key? key, required this.file}) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _videoPlayerController;
  late ChewieController _chewieController;

  @override
  void initState() {
    super.initState();
    _videoPlayerController = VideoPlayerController.file(widget.file);
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      autoInitialize: true,
      looping: false,
      allowFullScreen: true,
    );
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _videoPlayerController.value.aspectRatio,
      child: Chewie(
        controller: _chewieController,
      ),
    );
  }
}
