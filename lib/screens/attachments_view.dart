import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/utils.dart';
import '../core/widgets.dart';
import '../data/db.dart';
import '../data/models.dart';
import '../services/security.dart';

/// Image attachments (documents / session minutes) stored locally.
/// If [sessionId] is null all attachments of the case are shown.
class AttachmentsView extends StatelessWidget {
  final int caseId;
  final int? sessionId;
  const AttachmentsView({super.key, required this.caseId, this.sessionId});

  Future<void> _add(BuildContext context, ImageSource src) async {
    final picker = ImagePicker();
    final paths = <String>[];
    await Security.guard(() async {
      if (src == ImageSource.camera) {
        final x = await picker.pickImage(source: src, imageQuality: 85);
        if (x != null) paths.add(x.path);
      } else {
        final xs = await picker.pickMultiImage(imageQuality: 85);
        paths.addAll(xs.map((e) => e.path));
      }
    });
    for (final p in paths) {
      final name = await AppFiles.saveCopy(p);
      await Db.i.saveAttachment(Attachment(caseId: caseId, sessionId: sessionId, file: name));
    }
  }

  void _pickSource(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('التقاط صورة'),
            onTap: () {
              Navigator.pop(ctx);
              _add(context, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('اختيار من المعرض'),
            onTap: () {
              Navigator.pop(ctx);
              _add(context, ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Live<List<Attachment>>(
      load: () => Db.i.attachments(caseId, sessionId: sessionId),
      builder: (c, list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => _pickSource(c),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('إضافة صورة مستند / محضر'),
          ),
        ),
        const SizedBox(height: 10),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('لا توجد مرفقات'))
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final a in list)
              GestureDetector(
                onTap: () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => ImageViewScreen(file: a.file))),
                onLongPress: () async {
                  if (await confirm(c, 'حذف هذه الصورة؟', ok: 'حذف')) await Db.i.deleteAttachment(a);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(AppFiles.resolve(a.file).path),
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => Container(
                        width: 100, height: 100, color: Colors.black12, child: const Icon(Icons.broken_image)),
                  ),
                ),
              ),
          ]),
        if (list.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('اضغط للعرض، واضغط مطولًا للحذف', style: TextStyle(fontSize: 12)),
          ),
      ]),
    );
  }
}
