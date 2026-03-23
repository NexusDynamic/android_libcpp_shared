import 'package:flutter/material.dart';
import 'package:android_libcpp_shared/android_libcpp_shared.dart';
import 'dart:ffi' as ffi;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Flutter Demo',
    theme: ThemeData(primarySwatch: Colors.blue),
    home: const MyHomePage(),
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final ffi.DynamicLibrary? _lib;
  int _randomNumber = -1;

  @override
  void initState() {
    super.initState();
    _randomNumber = -1; // Initialize with an invalid random number.
    _lib = libCppShared;
  }

  /// Example of using a foreign function from libc++_shared.so.
  /// Generate a random number between 0 and 99 using the C standard library's
  /// rand() function.
  void getRandomInt() {
    if (_lib == null) {
      return;
    }
    final rand = _lib
        .lookup<ffi.NativeFunction<ffi.Int64 Function()>>('rand')
        .asFunction<int Function()>();
    final time = rand();
    setState(() {
      _randomNumber = time % 100; // Get a number between 0 and 99.
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Android libc++_shared.so Example')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _lib != null
                ? 'Random number from libc++_shared.so: $_randomNumber'
                : 'libc++_shared.so is not available on this platform.',
            textAlign: TextAlign.center,
          ),
          ElevatedButton(
            onPressed: () => getRandomInt(),
            child: const Text('Generate New Random Number'),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    _lib?.close();
    super.dispose();
  }
}
