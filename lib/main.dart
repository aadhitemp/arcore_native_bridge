import 'dart:math';
import 'dart:typed_data';
import 'package:arcore_flutter_plugin_example/camera_view.dart';
import 'package:arcore_flutter_plugin_example/screens/hello_world.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

import 'screens/multiple_augmented_images.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shape detection',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ShapeDetectionPage(
        camera: firstCamera,
      ),
    ),
  );
}

class ShapeDetectionPage extends StatefulWidget {
  const ShapeDetectionPage({super.key, required this.camera, this.imagePath});

  final CameraDescription camera;
  final String? imagePath;

  @override
  State<ShapeDetectionPage> createState() => _ShapeDetectionPageState();
}

class _ShapeDetectionPageState extends State<ShapeDetectionPage> {
  Uint8List? _image;
  // img.Image? _processedImage;
  String? _largestShape;
  @override
  void initState() {
    super.initState();
    if (widget.imagePath != null) {
      _image = File(widget.imagePath!).readAsBytesSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shape Detection'),
      ),
      body: Center(
        child: _image == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('No image selected.'),
                  ElevatedButton(
                    onPressed: _pickImage,
                    child: const Text('Open Gallery'),
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.all(8.0),
                child: SingleChildScrollView(
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Image.memory(_image!),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: MediaQuery.of(context).size.width,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Center(
                              child: Text(
                                  _largestShape ?? "No shape detected yet.")),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton(
                          onPressed: _detectLargestShape,
                          child: const Text('Detect Shape'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton(
                          onPressed: _pickImage,
                          child: const Text('Open Gallery'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) => HelloWorld()));
                          },
                          child: const Text('ARCore'),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (context) => Scaffold(
                                    body: ModelViewer(
                                        src: 'assets/sphere.gltf'))));
                          },
                          child: const Text('MVPlus'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (context) => TakePictureScreen(camera: widget.camera),
        )),
        tooltip: 'Pick Image',
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _image = bytes;
        // _processedImage = null;
        _largestShape = null;
      });
    }
  }

  Future<void> _convertImage() async {
    if (_image == null) return;

    img.Image originalImage = img.decodeImage(_image!)!;

    img.Image grayscaleImage = img.grayscale(originalImage);

    img.Image edgeDetectedImage = img.sobel(grayscaleImage);

    img.Image invertedImage = img.invert(edgeDetectedImage);

    Uint8List sketchBytes = Uint8List.fromList(img.encodeJpg(invertedImage));

    setState(() {
      _image = sketchBytes;
    });
  }

  void _detectLargestShape() {
    if (_image == null) return;

    _convertImage().then(
      (value) {
        // Decode the Sobel edge-detected image
        img.Image image = img.decodeImage(_image!)!;

        // Scan the image to find contours (connected shapes)
        List<Shape> shapes = _findShapes(image);

        // Find the largest shape
        if (shapes.isNotEmpty) {
          Shape largestShape = shapes
              .reduce((curr, next) => curr.area > next.area ? curr : next);
          setState(() {
            _largestShape =
                "Largest Shape: ${largestShape.type} with area: ${largestShape.area}";
          });
        } else {
          setState(() {
            _largestShape = "No shapes detected.";
          });
        }
      },
    );
  }

  List<Shape> _findShapes(img.Image image) {
    List<Shape> shapes = [];
    List<List<bool>> visited =
        List.generate(image.height, (_) => List.filled(image.width, false));

    // Scan through the image
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        if (_isEdge(image, x, y) && !visited[y][x]) {
          List<Point> contour = _traceContour(image, x, y, visited);
          if (contour.isNotEmpty) {
            Shape shape = _approximateShape(contour);
            shapes.add(shape);
          }
        }
      }
    }

    return shapes;
  }

  bool _isEdge(img.Image image, int x, int y) {
    int brightness = img.getLuminance(image.getPixel(x, y).clone()).toInt();
    return brightness < 128; // Adjust threshold based on the edge detection
  }

  List<Point> _traceContour(
      img.Image image, int startX, int startY, List<List<bool>> visited) {
    List<Point> contour = [];
    List<Point> stack = [Point(startX, startY)];

    while (stack.isNotEmpty) {
      Point p = stack.removeLast();
      if (p.x >= 0 &&
          p.x < image.width &&
          p.y >= 0 &&
          p.y < image.height &&
          !visited[p.y][p.x] &&
          _isEdge(image, p.x, p.y)) {
        contour.add(p);
        visited[p.y][p.x] = true;

        // Explore neighbors
        stack.add(Point(p.x + 1, p.y));
        stack.add(Point(p.x - 1, p.y));
        stack.add(Point(p.x, p.y + 1));
        stack.add(Point(p.x, p.y - 1));
      }
    }

    return contour;
  }

  Shape _approximateShape(List<Point> contour) {
    // Calculate the bounding box first
    int minX = contour.first.x, maxX = contour.first.x;
    int minY = contour.first.y, maxY = contour.first.y;

    for (Point p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    int width = maxX - minX;
    int height = maxY - minY;
    int area = width * height;

    // Use the bounding box to calculate aspect ratio
    double aspectRatio = width / height;

    // Classify the shape by number of vertices after approximating the contour
    List<Point> approxContour = _approximatePolygon(contour, tolerance: 5.0);

    String shapeType;
    if (approxContour.length == 3) {
      shapeType = "Triangle";
    } else if (approxContour.length == 4) {
      // Check if it's a square or rectangle
      if (aspectRatio > 0.9 && aspectRatio < 1.1) {
        shapeType = "Square";
      } else {
        shapeType = "Rectangle";
      }
    } else if (_isCircle(contour)) {
      shapeType = "Circle";
    } else {
      shapeType = "Polygon with ${approxContour.length} sides";
      if (approxContour.length > 1000) shapeType = "Circle";
    }

    return Shape(
      type: shapeType,
      area: area,
      boundingBox: Rect.fromLTRB(
          minX.toDouble(), minY.toDouble(), maxX.toDouble(), maxY.toDouble()),
    );
  }

  bool _isCircle(List<Point> contour) {
    // Calculate the bounding box to get the approximate diameter
    int minX = contour.first.x, maxX = contour.first.x;
    int minY = contour.first.y, maxY = contour.first.y;

    for (Point p in contour) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    int width = maxX - minX;
    int height = maxY - minY;

    // Calculate aspect ratio
    double aspectRatio = width / height;

    // Check if the contour is roughly circular
    if (aspectRatio > 0.9 && aspectRatio < 1.1) {
      double radius = width / 2.0;
      double contourArea =
          contour.length.toDouble(); // Approximate the area by length
      double circleArea = 3.14159 * radius * radius;

      // If the contour's length matches the area of a circle, it is likely a circle
      return (contourArea / circleArea > 0.8 && contourArea / circleArea < 1.2);
    }

    return false;
  }

  List<Point> _approximatePolygon(List<Point> contour,
      {double tolerance = 20.0}) {
    // Approximate the contour with fewer points based on a tolerance
    // A higher tolerance reduces the number of points and simplifies the shape.
    List<Point> approx = [];
    approx.add(contour.first);

    for (int i = 1; i < contour.length - 1; i++) {
      if (_distance(approx.last, contour[i]) > tolerance) {
        approx.add(contour[i]);
      }
    }

    // Close the contour
    approx.add(contour.last);
    return approx;
  }

  double _distance(Point p1, Point p2) {
    return sqrt((p1.x - p2.x) * (p1.x - p2.x) + (p1.y - p2.y) * (p1.y - p2.y))
        .toDouble();
  }
}

class Point {
  final int x, y;
  Point(this.x, this.y);
}

class Shape {
  final String type;
  final int area;
  final Rect boundingBox;

  Shape({required this.type, required this.area, required this.boundingBox});
}
