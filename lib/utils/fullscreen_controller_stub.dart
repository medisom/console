import 'package:flutter/foundation.dart';

typedef FullscreenDisposer = VoidCallback;

bool fullscreenIsSupportedImpl() => false;

bool fullscreenIsActiveImpl() => false;

Future<void> fullscreenEnterImpl() async {}

Future<void> fullscreenExitImpl() async {}

FullscreenDisposer registerFullscreenListenerImpl({required VoidCallback onChanged}) => () {};
