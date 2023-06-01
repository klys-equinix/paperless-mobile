import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/core/repository/label_repository.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';
import 'package:paperless_mobile/core/service/file_service.dart';

part 'document_upload_state.dart';

class DocumentUploadCubit extends Cubit<DocumentUploadState> {
  final PaperlessDocumentsApi _documentApi;

  final LabelRepository _labelRepository;

  final LocalNotificationService _notificationService;

  DocumentUploadCubit(this._labelRepository, this._documentApi, this._notificationService)
      : super(const DocumentUploadState()) {
    _labelRepository.addListener(
      this,
      onChanged: (labels) {
        emit(state.copyWith(
          correspondents: labels.correspondents,
          documentTypes: labels.documentTypes,
          tags: labels.tags,
        ));
      },
    );
  }

  Future<String?> upload(
    Uint8List bytes, {
    required String filename,
    required String title,
    int? documentType,
    int? correspondent,
    Iterable<int> tags = const [],
    DateTime? createdAt,
    int? asn,
  }) async {
    return await _documentApi.create(
      bytes,
      filename: filename,
      title: title,
      correspondent: correspondent,
      documentType: documentType,
      tags: tags,
      createdAt: createdAt,
      asn: asn,
    );
  }

  Future<void> saveLocally(
      Uint8List bytes, String fileName, String preferredLocaleSubtag
      ) async {
    var file = await FileService.saveToFile(bytes, fileName);
    _notificationService.notifyFileSaved(
      filename: fileName,
      filePath: file.path,
      finished: true,
      locale: preferredLocaleSubtag,
    );
  }

  @override
  Future<void> close() async {
    _labelRepository.removeListener(this);
    return super.close();
  }
}
