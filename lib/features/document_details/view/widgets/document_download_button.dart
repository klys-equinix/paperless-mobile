import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/core/service/file_service.dart';
import 'package:paperless_mobile/di_initializer.dart';
import 'package:paperless_mobile/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/generated/l10n.dart';
import 'package:paperless_mobile/util.dart';

class DocumentDownloadButton extends StatefulWidget {
  final DocumentModel? document;
  const DocumentDownloadButton({super.key, required this.document});

  @override
  State<DocumentDownloadButton> createState() => _DocumentDownloadButtonState();
}

class _DocumentDownloadButtonState extends State<DocumentDownloadButton> {
  bool _isDownloadPending = false;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isDownloadPending
          ? const SizedBox(
              child: CircularProgressIndicator(),
              height: 16,
              width: 16,
            )
          : const Icon(Icons.download),
      onPressed: Platform.isAndroid && widget.document != null
          ? () => _onDownload(widget.document!)
          : null,
    ).padded(const EdgeInsets.only(right: 4));
  }

  Future<void> _onDownload(DocumentModel document) async {
    if (!Platform.isAndroid) {
      showSnackBar(
          context, "This feature is currently only supported on Android!");
      return;
    }
    setState(() => _isDownloadPending = true);
    try {
      final bytes = await getIt<PaperlessDocumentsApi>().download(document);
      final Directory dir = await FileService.downloadsDirectory;
      String filePath = "${dir.path}/${document.originalFileName}";
      //TODO: Add replacement mechanism here (ask user if file should be replaced if exists)
      await File(filePath).writeAsBytes(bytes);
      showSnackBar(context, S.of(context).documentDownloadSuccessMessage);
    } on PaperlessServerException catch (error, stackTrace) {
      showErrorMessage(context, error, stackTrace);
    } catch (error) {
      showGenericError(context, error);
    } finally {
      setState(() => _isDownloadPending = false);
    }
  }
}
