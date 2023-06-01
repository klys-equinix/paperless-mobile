import 'dart:convert';
import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/features/notifications/converters/notification_tap_response_payload.dart';
import 'package:paperless_mobile/features/notifications/models/notification_payloads/notification_action/create_document_success_payload.dart';
import 'package:paperless_mobile/features/notifications/models/notification_payloads/notification_tap/open_downloaded_document_payload.dart';
import 'package:paperless_mobile/features/notifications/models/notification_actions.dart';
import 'package:paperless_mobile/features/notifications/models/notification_channels.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

class LocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  LocalNotificationService();

  Future<void> initialize() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('paperless_logo_green');
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
      onDidReceiveLocalNotification: onDidReceiveLocalNotification,
    );
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );
    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      onDidReceiveBackgroundNotificationResponse:
          onDidReceiveBackgroundNotificationResponse,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestPermission();
  }

  Future<void> notifyFileDownload({
    required DocumentModel document,
    required String filename,
    required String filePath,
    required bool finished,
    required String locale,
  }) async {
    final tr = await S.delegate.load(Locale(locale));

    int id = document.id;
    await _plugin.show(
      id,
      filename,
      finished
          ? tr.notificationDownloadComplete
          : tr.notificationDownloadingDocument,
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannel.documentDownload.id + "_${document.id}",
          NotificationChannel.documentDownload.name,
          ongoing: !finished,
          indeterminate: true,
          importance: Importance.max,
          priority: Priority.high,
          showProgress: !finished,
          when: DateTime.now().millisecondsSinceEpoch,
          category: AndroidNotificationCategory.progress,
          icon: finished ? 'file_download_done' : 'downloading',
        ),
        iOS: DarwinNotificationDetails(
          attachments: [
            DarwinNotificationAttachment(
              filePath,
            ),
          ],
        ),
      ),
      payload: jsonEncode(
        OpenDownloadedDocumentPayload(
          filePath: filePath,
        ).toJson(),
      ),
    ); //TODO: INTL
  }

  Future<void> notifyFileSaved({
    required String filename,
    required String filePath,
    required bool finished,
    required String locale,
  }) async {
    final tr = await S.delegate.load(Locale(locale));

    await _plugin.show(
      filePath.hashCode,
      filename,
      finished
          ? tr.notificationDownloadComplete
          : tr.notificationDownloadingDocument,
      NotificationDetails(
        android: AndroidNotificationDetails(
          NotificationChannel.documentDownload.id + "_$filename",
          NotificationChannel.documentDownload.name,
          ongoing: !finished,
          indeterminate: true,
          importance: Importance.max,
          priority: Priority.high,
          showProgress: !finished,
          when: DateTime.now().millisecondsSinceEpoch,
          category: AndroidNotificationCategory.progress,
          icon: finished ? 'file_download_done' : 'downloading',
        ),
        iOS: DarwinNotificationDetails(
          attachments: [
            DarwinNotificationAttachment(
              filePath,
            ),
          ],
        ),
      ),
      payload: jsonEncode(
        OpenDownloadedDocumentPayload(
          filePath: filePath,
        ).toJson(),
      ),
    ); //TODO: INTL
  }


  //TODO: INTL
  Future<void> notifyTaskChanged(Task task) {
    log("[LocalNotificationService] notifyTaskChanged: ${task.toString()}");
    int id = task.id;
    final status = task.status;
    late String title;
    late String? body;
    late int timestampMillis;
    bool showProgress =
        status == TaskStatus.started || status == TaskStatus.pending;
    dynamic payload;
    switch (status) {
      case TaskStatus.started:
        title = "Document received";
        body = task.taskFileName;
        timestampMillis = task.dateCreated.millisecondsSinceEpoch;
        break;
      case TaskStatus.pending:
        title = "Processing document...";
        body = task.taskFileName;
        timestampMillis = task.dateCreated.millisecondsSinceEpoch;
        break;
      case TaskStatus.failure:
        title = "Failed to process document";
        body = "Document ${task.taskFileName} was rejected by the server.";
        timestampMillis = task.dateCreated.millisecondsSinceEpoch;
        break;
      case TaskStatus.success:
        title = "Document successfully created";
        body = task.taskFileName;
        timestampMillis = task.dateDone!.millisecondsSinceEpoch;
        payload = CreateDocumentSuccessPayload(
          task.relatedDocument!,
        );
        break;
      default:
        break;
    }
    return _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          '${NotificationChannel.task.id}_${task.id}',
          NotificationChannel.task.name,
          category: AndroidNotificationCategory.status,
          ongoing: showProgress,
          showProgress: showProgress,
          maxProgress: 100,
          when: timestampMillis,
          indeterminate: true,
          actions: status == TaskStatus.success
              ? [
                  //TODO: Implement once moved to new routing
                  // AndroidNotificationAction(
                  //   NotificationResponseAction.openCreatedDocument.name,
                  //   "Open",
                  //   showsUserInterface: true,
                  // ),
                  // AndroidNotificationAction(
                  //   NotificationResponseAction.acknowledgeCreatedDocument.name,
                  //   "Acknowledge",
                  // ),
                ]
              : [],
        ),
        //TODO: Add darwin support
      ),
      payload: jsonEncode(payload),
    );
  }

  void onDidReceiveLocalNotification(
    int id,
    String? title,
    String? body,
    String? payload,
  ) {
    debugPrint("onDidReceiveNotification!");
  }

  void onDidReceiveNotificationResponse(NotificationResponse response) {
    debugPrint(
      "Received Notification ${response.id}: Action is ${response.actionId}): ${response.payload}",
    );
    switch (response.notificationResponseType) {
      case NotificationResponseType.selectedNotification:
        if (response.payload != null) {
          final payload =
              const NotificationTapResponsePayloadConverter().fromJson(
            jsonDecode(response.payload!),
          );
          _handleResponseTapAction(payload.type, response);
        }

        break;
      case NotificationResponseType.selectedNotificationAction:
        final action =
            NotificationResponseButtonAction.values.byName(response.actionId!);
        _handleResponseButtonAction(action, response);
        break;
    }
  }

  void _handleResponseButtonAction(
    NotificationResponseButtonAction action,
    NotificationResponse response,
  ) {
    switch (action) {
      case NotificationResponseButtonAction.openCreatedDocument:
        final payload = CreateDocumentSuccessPayload.fromJson(
          jsonDecode(response.payload!),
        );
        log("Navigate to document ${payload.documentId}");
        break;
      case NotificationResponseButtonAction.acknowledgeCreatedDocument:
        final payload = CreateDocumentSuccessPayload.fromJson(
          jsonDecode(response.payload!),
        );
        log("Acknowledge document ${payload.documentId}");
        break;
    }
  }

  void _handleResponseTapAction(
    NotificationResponseOpenAction type,
    NotificationResponse response,
  ) {
    switch (type) {
      case NotificationResponseOpenAction.openDownloadedDocumentPath:
        final payload = OpenDownloadedDocumentPayload.fromJson(
            jsonDecode(response.payload!));
        OpenFilex.open(payload.filePath);
        break;
    }
  }
}

void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  //TODO: When periodic background inbox check is implemented, notification tap is handled here
  debugPrint(response.toString());
}
