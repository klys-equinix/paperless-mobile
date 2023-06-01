import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:hive/hive.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/core/bloc/connectivity_cubit.dart';
import 'package:paperless_mobile/core/config/hive/hive_config.dart';
import 'package:paperless_mobile/core/database/tables/global_settings.dart';
import 'package:paperless_mobile/core/database/tables/local_user_app_state.dart';
import 'package:paperless_mobile/core/notifier/document_changed_notifier.dart';
import 'package:paperless_mobile/core/repository/label_repository.dart';
import 'package:paperless_mobile/core/repository/user_repository.dart';
import 'package:paperless_mobile/features/document_bulk_action/cubit/document_bulk_action_cubit.dart';
import 'package:paperless_mobile/features/document_bulk_action/view/widgets/fullscreen_bulk_edit_label_page.dart';
import 'package:paperless_mobile/features/document_bulk_action/view/widgets/fullscreen_bulk_edit_tags_widget.dart';
import 'package:paperless_mobile/features/document_search/cubit/document_search_cubit.dart';
import 'package:paperless_mobile/features/document_search/view/document_search_page.dart';
import 'package:paperless_mobile/features/document_upload/cubit/document_upload_cubit.dart';
import 'package:paperless_mobile/features/document_upload/view/document_upload_preparation_page.dart';
import 'package:paperless_mobile/features/home/view/model/api_version.dart';
import 'package:paperless_mobile/features/linked_documents/cubit/linked_documents_cubit.dart';
import 'package:paperless_mobile/features/linked_documents/view/linked_documents_page.dart';
import 'package:paperless_mobile/features/notifications/services/local_notification_service.dart';
import 'package:paperless_mobile/features/saved_view/cubit/saved_view_cubit.dart';
import 'package:paperless_mobile/features/saved_view/view/add_saved_view_page.dart';
import 'package:paperless_mobile/features/saved_view_details/cubit/saved_view_details_cubit.dart';
import 'package:paperless_mobile/features/saved_view_details/view/saved_view_details_page.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';
import 'package:paperless_mobile/routes/document_details_route.dart';
import 'package:provider/provider.dart';

// These are convenience methods for nativating to views without having to pass providers around explicitly.
// Providers unfortunately have to be passed to the routes since they are children of the Navigator, not ancestors.

Future<void> pushDocumentSearchPage(BuildContext context) {
  final currentUser =
      Hive.box<GlobalSettings>(HiveBoxes.globalSettings).getValue()!.currentLoggedInUser;
  final userRepo = context.read<UserRepository>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: context.read<LabelRepository>()),
          Provider.value(value: context.read<PaperlessDocumentsApi>()),
          Provider.value(value: context.read<DocumentChangedNotifier>()),
          Provider.value(value: context.read<CacheManager>()),
          Provider.value(value: userRepo),
        ],
        builder: (context, _) {
          return BlocProvider(
            create: (context) => DocumentSearchCubit(
              context.read(),
              context.read(),
              context.read(),
              Hive.box<LocalUserAppState>(HiveBoxes.localUserAppState).get(currentUser)!,
            ),
            child: const DocumentSearchPage(),
          );
        },
      ),
    ),
  );
}

Future<void> pushDocumentDetailsRoute(
  BuildContext context, {
  required DocumentModel document,
  bool isLabelClickable = true,
  bool allowEdit = true,
  String? titleAndContentQueryString,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: context.read<ApiVersion>()),
          Provider.value(value: context.read<LabelRepository>()),
          Provider.value(value: context.read<DocumentChangedNotifier>()),
          Provider.value(value: context.read<PaperlessDocumentsApi>()),
          Provider.value(value: context.read<LocalNotificationService>()),
          Provider.value(value: context.read<CacheManager>()),
          Provider.value(value: context.read<ConnectivityCubit>()),
          if (context.read<ApiVersion>().hasMultiUserSupport)
            Provider.value(value: context.read<UserRepository>()),
        ],
        child: DocumentDetailsRoute(
          document: document,
          isLabelClickable: isLabelClickable,
        ),
      ),
    ),
  );
}

Future<void> pushSavedViewDetailsRoute(
  BuildContext context, {
  required SavedView savedView,
}) {
  final apiVersion = context.read<ApiVersion>();
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: apiVersion),
          if (apiVersion.hasMultiUserSupport) Provider.value(value: context.read<UserRepository>()),
          Provider.value(value: context.read<LabelRepository>()),
          Provider.value(value: context.read<DocumentChangedNotifier>()),
          Provider.value(value: context.read<PaperlessDocumentsApi>()),
          Provider.value(value: context.read<CacheManager>()),
          Provider.value(value: context.read<ConnectivityCubit>()),
        ],
        builder: (_, child) {
          return BlocProvider(
            create: (context) => SavedViewDetailsCubit(
              context.read(),
              context.read(),
              context.read(),
              LocalUserAppState.current,
              savedView: savedView,
            ),
            child: SavedViewDetailsPage(onDelete: context.read<SavedViewCubit>().remove),
          );
        },
      ),
    ),
  );
}

Future<SavedView?> pushAddSavedViewRoute(BuildContext context, {required DocumentFilter filter}) {
  return Navigator.of(context).push<SavedView?>(
    MaterialPageRoute(
      builder: (_) => AddSavedViewPage(
        currentFilter: filter,
        correspondents: context.read<LabelRepository>().state.correspondents,
        documentTypes: context.read<LabelRepository>().state.documentTypes,
        storagePaths: context.read<LabelRepository>().state.storagePaths,
        tags: context.read<LabelRepository>().state.tags,
      ),
    ),
  );
}

Future<void> pushLinkedDocumentsView(BuildContext context, {required DocumentFilter filter}) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: context.read<ApiVersion>()),
          Provider.value(value: context.read<LabelRepository>()),
          Provider.value(value: context.read<DocumentChangedNotifier>()),
          Provider.value(value: context.read<PaperlessDocumentsApi>()),
          Provider.value(value: context.read<LocalNotificationService>()),
          Provider.value(value: context.read<CacheManager>()),
          Provider.value(value: context.read<ConnectivityCubit>()),
          if (context.read<ApiVersion>().hasMultiUserSupport)
            Provider.value(value: context.read<UserRepository>()),
        ],
        builder: (context, _) => BlocProvider(
          create: (context) => LinkedDocumentsCubit(
            filter,
            context.read(),
            context.read(),
            context.read(),
          ),
          child: const LinkedDocumentsPage(),
        ),
      ),
    ),
  );
}

Future<void> pushBulkEditCorrespondentRoute(
  BuildContext context, {
  required List<DocumentModel> selection,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ..._getRequiredBulkEditProviders(context),
        ],
        builder: (_, __) => BlocProvider(
          create: (_) => DocumentBulkActionCubit(
            context.read(),
            context.read(),
            context.read(),
            selection: selection,
          ),
          child: BlocBuilder<DocumentBulkActionCubit, DocumentBulkActionState>(
            builder: (context, state) {
              return FullscreenBulkEditLabelPage(
                options: state.correspondents,
                selection: state.selection,
                labelMapper: (document) => document.correspondent,
                leadingIcon: const Icon(Icons.person_outline),
                hintText: S.of(context)!.startTyping,
                onSubmit: context.read<DocumentBulkActionCubit>().bulkModifyCorrespondent,
                assignMessageBuilder: (int count, String name) {
                  return S.of(context)!.bulkEditCorrespondentAssignMessage(
                        name,
                        count,
                      );
                },
                removeMessageBuilder: (int count) {
                  return S.of(context)!.bulkEditCorrespondentRemoveMessage(count);
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> pushBulkEditStoragePathRoute(
  BuildContext context, {
  required List<DocumentModel> selection,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ..._getRequiredBulkEditProviders(context),
        ],
        builder: (_, __) => BlocProvider(
          create: (_) => DocumentBulkActionCubit(
            context.read(),
            context.read(),
            context.read(),
            selection: selection,
          ),
          child: BlocBuilder<DocumentBulkActionCubit, DocumentBulkActionState>(
            builder: (context, state) {
              return FullscreenBulkEditLabelPage(
                options: state.storagePaths,
                selection: state.selection,
                labelMapper: (document) => document.storagePath,
                leadingIcon: const Icon(Icons.folder_outlined),
                hintText: S.of(context)!.startTyping,
                onSubmit: context.read<DocumentBulkActionCubit>().bulkModifyStoragePath,
                assignMessageBuilder: (int count, String name) {
                  return S.of(context)!.bulkEditStoragePathAssignMessage(
                        count,
                        name,
                      );
                },
                removeMessageBuilder: (int count) {
                  return S.of(context)!.bulkEditStoragePathRemoveMessage(count);
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> pushBulkEditTagsRoute(
  BuildContext context, {
  required List<DocumentModel> selection,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ..._getRequiredBulkEditProviders(context),
        ],
        builder: (_, __) => BlocProvider(
          create: (_) => DocumentBulkActionCubit(
            context.read(),
            context.read(),
            context.read(),
            selection: selection,
          ),
          child: Builder(builder: (context) {
            return const FullscreenBulkEditTagsWidget();
          }),
        ),
      ),
    ),
  );
}

Future<void> pushBulkEditDocumentTypeRoute(BuildContext context,
    {required List<DocumentModel> selection}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          ..._getRequiredBulkEditProviders(context),
        ],
        builder: (_, __) => BlocProvider(
          create: (_) => DocumentBulkActionCubit(
            context.read(),
            context.read(),
            context.read(),
            selection: selection,
          ),
          child: BlocBuilder<DocumentBulkActionCubit, DocumentBulkActionState>(
            builder: (context, state) {
              return FullscreenBulkEditLabelPage(
                options: state.documentTypes,
                selection: state.selection,
                labelMapper: (document) => document.documentType,
                leadingIcon: const Icon(Icons.description_outlined),
                hintText: S.of(context)!.startTyping,
                onSubmit: context.read<DocumentBulkActionCubit>().bulkModifyDocumentType,
                assignMessageBuilder: (int count, String name) {
                  return S.of(context)!.bulkEditDocumentTypeAssignMessage(
                        count,
                        name,
                      );
                },
                removeMessageBuilder: (int count) {
                  return S.of(context)!.bulkEditDocumentTypeRemoveMessage(count);
                },
              );
            },
          ),
        ),
      ),
    ),
  );
}

Future<DocumentUploadResult?> pushDocumentUploadPreparationPage(
  BuildContext context, {
  required Uint8List bytes,
  String? filename,
  String? fileExtension,
  String? title,
}) {
  final labelRepo = context.read<LabelRepository>();
  final docsApi = context.read<PaperlessDocumentsApi>();
  return Navigator.of(context).push<DocumentUploadResult>(
    MaterialPageRoute(
      builder: (_) => MultiProvider(
        providers: [
          Provider.value(value: labelRepo),
          Provider.value(value: docsApi),
        ],
        builder: (_, child) => BlocProvider(
          create: (_) => DocumentUploadCubit(
            context.read(),
            context.read(),
            context.read(),
          ),
          child: DocumentUploadPreparationPage(
            fileBytes: bytes,
            fileExtension: fileExtension,
            filename: filename,
            title: title,
          ),
        ),
      ),
    ),
  );
}

List<Provider> _getRequiredBulkEditProviders(BuildContext context) {
  return [
    Provider.value(value: context.read<PaperlessDocumentsApi>()),
    Provider.value(value: context.read<LabelRepository>()),
    Provider.value(value: context.read<DocumentChangedNotifier>()),
  ];
}
