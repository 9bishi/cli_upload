import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
// Add the IJKPlayer plugin import here

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
    List<Future<void>> uploadTasks = [];

    for (int i = 0; i < _selectedVideos.length; i++) {
      uploadTasks.add(_uploadVideo(i));
    }

    await Future.wait(uploadTasks);
  }

  Future<void> _uploadVideo(int index) async {
    File selectedVideo = _selectedVideos[index];
    double uploadProgress = 0.0;
    bool uploading = true;
    String uploadStatus = '';
    String? videoUrl;
    List<String> uploadRecords = [];

    setState(() {
      _uploadProgressList[index] = uploadProgress;
      _uploadingList[index] = uploading;
      _uploadStatusList[index] = uploadStatus;
      _videoUrlList[index] = videoUrl;
      _uploadRecordsList[index] = uploadRecords;
    });

    String apiUrl = 'https://cdn.cli.plus/api.php';

    FormData formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        selectedVideo.path,
        filename: path.basename(selectedVideo.path),
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
            uploadProgress = progress;
            _uploadProgressList[index] = uploadProgress;
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

        uploadRecords.add(DateTime.now().toString());

        setState(() {
          uploading = false;
          uploadStatus = '上传完成！';
          _uploadingList[index] = uploading;
          _uploadStatusList[index] = uploadStatus;
          videoUrl = videoUrl;
          _videoUrlList[index] = videoUrl;
          _uploadRecordsList[index] = uploadRecords;
        });
      } else {
        // 处理错误响应
        setState(() {
          uploading = false;
          uploadStatus = '上传失败';
          _uploadingList[index] = uploading;
          _uploadStatusList[index] = uploadStatus;
        });
        return;
      }
    } catch (error) {
      // 处理网络请求错误
      setState(() {
        uploading = false;
        uploadStatus = '上传失败';
        _uploadingList[index] = uploading;
        _uploadStatusList[index] = uploadStatus;
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
                height: 200.0,
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

