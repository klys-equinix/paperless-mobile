import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:hive/hive.dart';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:paperless_api/paperless_api.dart';
import 'package:paperless_mobile/constants.dart';
import 'package:paperless_mobile/core/config/hive/hive_config.dart';
import 'package:paperless_mobile/core/database/tables/global_settings.dart';
import 'package:paperless_mobile/core/database/tables/local_user_account.dart';
import 'package:paperless_mobile/core/repository/label_repository.dart';
import 'package:paperless_mobile/core/type/types.dart';
import 'package:paperless_mobile/extensions/flutter_extensions.dart';
import 'package:paperless_mobile/features/document_upload/cubit/document_upload_cubit.dart';
import 'package:paperless_mobile/features/edit_label/view/impl/add_correspondent_page.dart';
import 'package:paperless_mobile/features/edit_label/view/impl/add_document_type_page.dart';
import 'package:paperless_mobile/features/labels/tags/view/widgets/tags_form_field.dart';
import 'package:paperless_mobile/features/labels/view/widgets/label_form_field.dart';
import 'package:paperless_mobile/generated/l10n/app_localizations.dart';

import 'package:paperless_mobile/helpers/message_helpers.dart';
import 'package:paperless_mobile/helpers/permission_helpers.dart';
import 'package:permission_handler/permission_handler.dart';

class DocumentUploadResult {
  final bool success;
  final String? taskId;

  DocumentUploadResult(this.success, this.taskId);
}

class DocumentUploadPreparationPage extends StatefulWidget {
  final Uint8List fileBytes;
  final String? title;
  final String? filename;
  final String? fileExtension;

  const DocumentUploadPreparationPage({
    Key? key,
    required this.fileBytes,
    this.title,
    this.filename,
    this.fileExtension,
  }) : super(key: key);

  @override
  State<DocumentUploadPreparationPage> createState() => _DocumentUploadPreparationPageState();
}

class _DocumentUploadPreparationPageState extends State<DocumentUploadPreparationPage> {
  static const fkFileName = "filename";
  static final fileNameDateFormat = DateFormat("yyyy_MM_ddTHH_mm_ss");

  final GlobalKey<FormBuilderState> _formKey = GlobalKey();

  PaperlessValidationErrors _errors = {};
  bool _isUploadLoading = false;
  late bool _syncTitleAndFilename;
  bool _showDatePickerDeleteIcon = false;
  final _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _syncTitleAndFilename = widget.filename == null && widget.title == null;
    initializeDateFormatting();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(S.of(context)!.prepareDocument),
        bottom: _isUploadLoading
            ? const PreferredSize(
                child: LinearProgressIndicator(), preferredSize: Size.fromHeight(4.0))
            : null,
      ),
      bottomNavigationBar: _buildBottomAppBar(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
      floatingActionButton: Visibility(
        visible: MediaQuery.of(context).viewInsets.bottom == 0,
        child: FloatingActionButton.extended(
          onPressed: _onSubmit,
          label: Text(S.of(context)!.upload),
          icon: const Icon(Icons.upload),
        ),
      ),
      body: BlocBuilder<DocumentUploadCubit, DocumentUploadState>(
        builder: (context, state) {
          return FormBuilder(
            key: _formKey,
            child: ListView(
              children: [
                // Title
                FormBuilderTextField(
                  autovalidateMode: AutovalidateMode.always,
                  name: DocumentModel.titleKey,
                  initialValue: widget.title ?? "scan_${fileNameDateFormat.format(_now)}",
                  validator: (value) {
                    if (value?.trim().isEmpty ?? true) {
                      return S.of(context)!.thisFieldIsRequired;
                    }
                    return null;
                  },
                  decoration: InputDecoration(
                    labelText: S.of(context)!.title,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _formKey.currentState?.fields[DocumentModel.titleKey]?.didChange("");
                        if (_syncTitleAndFilename) {
                          _formKey.currentState?.fields[fkFileName]?.didChange("");
                        }
                      },
                    ),
                    errorText: _errors[DocumentModel.titleKey],
                  ),
                  onChanged: (value) {
                    final String transformedValue = _formatFilename(value ?? '');
                    if (_syncTitleAndFilename) {
                      _formKey.currentState?.fields[fkFileName]?.didChange(transformedValue);
                    }
                  },
                ),
                // Filename
                FormBuilderTextField(
                  autovalidateMode: AutovalidateMode.always,
                  readOnly: _syncTitleAndFilename,
                  enabled: !_syncTitleAndFilename,
                  name: fkFileName,
                  decoration: InputDecoration(
                    labelText: S.of(context)!.fileName,
                    suffixText: widget.fileExtension,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _formKey.currentState?.fields[fkFileName]?.didChange(''),
                    ),
                  ),
                  initialValue: widget.filename ?? "scan_${fileNameDateFormat.format(_now)}",
                ),
                // Synchronize title and filename
                SwitchListTile(
                  value: _syncTitleAndFilename,
                  onChanged: (value) {
                    setState(
                      () => _syncTitleAndFilename = value,
                    );
                    if (_syncTitleAndFilename) {
                      final String transformedValue = _formatFilename(
                          _formKey.currentState?.fields[DocumentModel.titleKey]?.value as String);
                      if (_syncTitleAndFilename) {
                        _formKey.currentState?.fields[fkFileName]?.didChange(transformedValue);
                      }
                    }
                  },
                  title: Text(
                    S.of(context)!.synchronizeTitleAndFilename,
                  ),
                ),
                // Created at
                FormBuilderDateTimePicker(
                  autovalidateMode: AutovalidateMode.always,
                  format: DateFormat.yMMMMd(),
                  inputType: InputType.date,
                  name: DocumentModel.createdKey,
                  initialValue: null,
                  onChanged: (value) {
                    setState(() => _showDatePickerDeleteIcon = value != null);
                  },
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.calendar_month_outlined),
                    labelText: S.of(context)!.createdAt + " *",
                    suffixIcon: _showDatePickerDeleteIcon
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _formKey.currentState!.fields[DocumentModel.createdKey]
                                  ?.didChange(null);
                            },
                          )
                        : null,
                  ),
                ),
                // Correspondent
                LabelFormField<Correspondent>(
                  showAnyAssignedOption: false,
                  showNotAssignedOption: false,
                  addLabelPageBuilder: (initialName) => RepositoryProvider.value(
                    value: context.read<LabelRepository>(),
                    child: AddCorrespondentPage(initialName: initialName),
                  ),
                  addLabelText: S.of(context)!.addCorrespondent,
                  labelText: S.of(context)!.correspondent + " *",
                  name: DocumentModel.correspondentKey,
                  options: state.correspondents,
                  prefixIcon: const Icon(Icons.person_outline),
                  allowSelectUnassigned: true,
                  canCreateNewLabel: LocalUserAccount.current.paperlessUser.hasPermission(
                    PermissionAction.add,
                    PermissionTarget.correspondent,
                  ),
                ),
                // Document type
                LabelFormField<DocumentType>(
                  showAnyAssignedOption: false,
                  showNotAssignedOption: false,
                  addLabelPageBuilder: (initialName) => RepositoryProvider.value(
                    value: context.read<LabelRepository>(),
                    child: AddDocumentTypePage(initialName: initialName),
                  ),
                  addLabelText: S.of(context)!.addDocumentType,
                  labelText: S.of(context)!.documentType + " *",
                  name: DocumentModel.documentTypeKey,
                  options: state.documentTypes,
                  prefixIcon: const Icon(Icons.description_outlined),
                  allowSelectUnassigned: true,
                  canCreateNewLabel: LocalUserAccount.current.paperlessUser.hasPermission(
                    PermissionAction.add,
                    PermissionTarget.documentType,
                  ),
                ),
                TagsFormField(
                  name: DocumentModel.tagsKey,
                  allowCreation: true,
                  allowExclude: false,
                  allowOnlySelection: true,
                  options: state.tags,
                ),
                Text(
                  "* " + S.of(context)!.uploadInferValuesHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 300),
              ].padded(),
            ),
          );
        },
      ),
    );
  }

  void _onSubmit() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      final cubit = context.read<DocumentUploadCubit>();
      try {
        setState(() => _isUploadLoading = true);

        final fv = _formKey.currentState!.value;

        final createdAt = fv[DocumentModel.createdKey] as DateTime?;
        final title = fv[DocumentModel.titleKey] as String;
        final docType = (fv[DocumentModel.documentTypeKey] as IdQueryParameter?)
            ?.whenOrNull(fromId: (id) => id);
        final tags = (fv[DocumentModel.tagsKey] as TagsQuery?)
                ?.whenOrNull(ids: (include, exclude) => include) ??
            [];
        final correspondent = (fv[DocumentModel.correspondentKey] as IdQueryParameter?)
            ?.whenOrNull(fromId: (id) => id);
        final asn = fv[DocumentModel.asnKey] as int?;
        final taskId = await cubit.upload(
          widget.fileBytes,
          filename: _padWithExtension(
            _formKey.currentState?.value[fkFileName],
            widget.fileExtension,
          ),
          title: title,
          documentType: docType,
          correspondent: correspondent,
          tags: tags,
          createdAt: createdAt,
          asn: asn,
        );
        showSnackBar(
          context,
          S.of(context)!.documentSuccessfullyUploadedProcessing,
        );
        Navigator.pop(
          context,
          DocumentUploadResult(true, taskId),
        );
      } on PaperlessServerException catch (error, stackTrace) {
        showErrorMessage(context, error, stackTrace);
      } on PaperlessValidationErrors catch (errors) {
        setState(() => _errors = errors);
      } catch (unknownError, stackTrace) {
        debugPrint(unknownError.toString());
        showErrorMessage(context, const PaperlessServerException.unknown(), stackTrace);
      } finally {
        setState(() {
          _isUploadLoading = false;
        });
      }
    }
  }

  BlocBuilder<DocumentUploadCubit, DocumentUploadState> _buildBottomAppBar() {
    return BlocBuilder<DocumentUploadCubit, DocumentUploadState>(
      builder: (context, state) {
        return BottomAppBar(
          child: BlocBuilder<DocumentUploadCubit, DocumentUploadState>(
            builder: (context, connectivityState) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    tooltip: "Save a local copy",
                    icon: const Icon(Icons.download),
                    onPressed: () => _onLocalSave(),
                  ).paddedOnly(right: 4.0),
                ],
              );
            },
          ),
        );
      },
    );
  }


  String _padWithExtension(String source, [String? extension]) {
    final ext = extension ?? '.pdf';
    return source.endsWith(ext) ? source : '$source$ext';
  }

  String _formatFilename(String source) {
    return source.replaceAll(RegExp(r"[\W_]"), "_").toLowerCase();
  }

  Future<void> _onLocalSave() async {
    final cubit = context.read<DocumentUploadCubit>();

    try {
      final globalSettings = Hive.box<GlobalSettings>(HiveBoxes.globalSettings).getValue()!;
      if (Platform.isAndroid && androidInfo!.version.sdkInt <= 29) {
        final isGranted = await askForPermission(Permission.storage);
        if (!isGranted) {
          return;
          //TODO: Ask user to grant permissions
        }
      }
      final title = (_formKey.currentState?.fields[fkFileName]?.value ?? widget.filename) as String;

      var fileName = "$title.${widget.fileExtension}";

      await cubit.saveLocally(widget.fileBytes, fileName, globalSettings.preferredLocaleSubtag);
    } catch (error) {
      showGenericError(context, error);
    }
  }

}
