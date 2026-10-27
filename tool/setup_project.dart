// Run once, right after `flutter create`:
//     dart run tool/setup_project.dart
// It makes the small Android settings DukanDar needs (notifications,
// internet permission, app name) and removes the sample test.
import 'dart:io';

void main() {
  _fixSampleTest();
  _patchGradle();
  _patchManifest();
  stdout.writeln('\nDone. Now run:  flutter pub get');
}

void _fixSampleTest() {
  final f = File('test/widget_test.dart');
  if (f.existsSync()) {
    f.deleteSync();
    stdout.writeln('Removed sample test/widget_test.dart');
  }
}

void _patchGradle() {
  File? f;
  var kts = true;
  if (File('android/app/build.gradle.kts').existsSync()) {
    f = File('android/app/build.gradle.kts');
  } else if (File('android/app/build.gradle').existsSync()) {
    f = File('android/app/build.gradle');
    kts = false;
  }
  if (f == null) {
    stdout.writeln('! android/app/build.gradle not found. Run '
        '`flutter create --platforms=android,windows .` first.');
    return;
  }
  var text = f.readAsStringSync();
  if (text.contains('desugar_jdk_libs')) {
    stdout.writeln('Gradle already patched.');
    return;
  }

  // 1. turn on core library desugaring (needed by the notifications plugin)
  final compileOptions = RegExp(r'compileOptions\s*\{');
  if (compileOptions.hasMatch(text)) {
    text = text.replaceFirstMapped(
      compileOptions,
      (m) => kts
          ? '${m[0]}\n        isCoreLibraryDesugaringEnabled = true'
          : '${m[0]}\n        coreLibraryDesugaringEnabled true',
    );
  } else {
    final android = RegExp(r'android\s*\{');
    text = text.replaceFirstMapped(
      android,
      (m) => kts
          ? '${m[0]}\n    compileOptions {\n        isCoreLibraryDesugaringEnabled = true\n    }'
          : '${m[0]}\n    compileOptions {\n        coreLibraryDesugaringEnabled true\n    }',
    );
  }

  // 2. the desugaring library itself
  final dep = kts
      ? '    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
      : "    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'";
  final deps = RegExp(r'\ndependencies\s*\{');
  if (deps.hasMatch(text)) {
    text = text.replaceFirstMapped(deps, (m) => '${m[0]}\n$dep');
  } else {
    text = '$text\ndependencies {\n$dep\n}\n';
  }

  f.writeAsStringSync(text);
  stdout.writeln('Patched ${f.path}');
}

void _patchManifest() {
  final f = File('android/app/src/main/AndroidManifest.xml');
  if (!f.existsSync()) {
    stdout.writeln('! AndroidManifest.xml not found.');
    return;
  }
  var text = f.readAsStringSync();
  if (text.contains('ScheduledNotificationReceiver')) {
    stdout.writeln('Manifest already patched.');
    return;
  }

  const permissions = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
''';
  text = text.replaceFirst('<application', '$permissions    <application');

  const receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
''';
  text = text.replaceFirst('</application>', '$receivers    </application>');

  // friendly app name under the icon
  text = text.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="DukanDar"');

  f.writeAsStringSync(text);
  stdout.writeln('Patched AndroidManifest.xml');
}
