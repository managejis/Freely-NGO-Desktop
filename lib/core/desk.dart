import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Desktop replacements for the phone's share sheet and image picker.
class Desk {
  /// Asks where to save [bytes] ("Save as" dialog) and writes the file. Returns the saved path, or null when cancelled.
  static Future<String?> saveBytes(String suggestedName, List<int> bytes, {String? ext}) async {
    final e = ext ?? p.extension(suggestedName).replaceFirst('.', '');
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save $suggestedName',
      fileName: suggestedName,
      type: e.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: e.isEmpty ? null : [e],
    );
    if (path == null) return null;
    final full = (e.isNotEmpty && p.extension(path).isEmpty) ? '$path.$e' : path;
    await File(full).writeAsBytes(bytes, flush: true);
    return full;
  }

  /// Copies [text] to the clipboard (there is no share sheet on a PC) and says so.
  static Future<void> copyText(BuildContext context, String text, {String message = 'Copied to the clipboard - paste it into WhatsApp, SMS or e-mail'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Lets the user choose a picture and returns it as a small JPEG (max 160 x 160) in base64, ready to store as the NGO logo.
  static Future<String?> pickLogoBase64() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final f = r?.files.single;
    if (f == null) return null;
    final Uint8List bytes = f.bytes ?? await File(f.path!).readAsBytes();
    final im = img.decodeImage(bytes);
    if (im == null) throw Exception('This file is not a picture that can be used as a logo');
    final small = img.copyResize(im, width: im.width >= im.height ? 160 : null, height: im.height > im.width ? 160 : null);
    return base64Encode(img.encodeJpg(small, quality: 75));
  }
}
