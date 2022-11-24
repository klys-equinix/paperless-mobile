import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:paperless_mobile/features/documents/model/bulk_edit.model.dart';
import 'package:paperless_mobile/features/documents/model/document.model.dart';
import 'package:paperless_mobile/features/documents/model/document_filter.dart';
import 'package:paperless_mobile/features/documents/model/query_parameters/sort_field.dart';
import 'package:paperless_mobile/features/documents/model/query_parameters/tags_query.dart';
import 'package:paperless_mobile/features/documents/repository/document_repository.dart';
import 'package:paperless_mobile/features/inbox/bloc/state/inbox_state.dart';
import 'package:paperless_mobile/features/labels/repository/label_repository.dart';

@injectable
class InboxCubit extends Cubit<InboxState> {
  final LabelRepository _labelRepository;
  final DocumentRepository _documentRepository;

  InboxCubit(this._labelRepository, this._documentRepository)
      : super(const InboxState());

  ///
  /// Fetches inbox tag ids and loads the inbox items (documents).
  ///
  Future<void> initialize() async {
    final inboxTags = await _labelRepository.getTags().then(
        (value) => value.where((t) => t.isInboxTag ?? false).map((t) => t.id!));
    final inboxDocuments = await _documentRepository
        .find(DocumentFilter(
          tags: AnyAssignedTagsQuery(tagIds: inboxTags),
          sortField: SortField.added,
        ))
        .then((psr) => psr.results);
    final newState = InboxState(
      isLoaded: true,
      inboxItems: inboxDocuments,
      inboxTags: inboxTags,
    );
    emit(newState);
  }

  Future<void> reloadInbox() async {
    if (!state.isLoaded) {
      throw "State has not yet loaded. Ensure the state is loaded when calling this method!";
    }
    final inboxDocuments = await _documentRepository
        .find(DocumentFilter(
          tags: AnyAssignedTagsQuery(tagIds: state.inboxTags),
          sortField: SortField.added,
        ))
        .then((psr) => psr.results);
    emit(InboxState(
      isLoaded: true,
      inboxItems: inboxDocuments,
      inboxTags: state.inboxTags,
    ));
  }

  ///
  /// Updates the document with all inbox tags removed and removes the document
  /// from the currently loaded inbox documents.
  ///
  Future<Iterable<int>> remove(DocumentModel document) async {
    if (!state.isLoaded) {
      throw "State has not yet loaded. Ensure the state is loaded when calling this method!";
    }
    final tagsToRemove =
        document.tags.toSet().intersection(state.inboxTags.toSet());

    final updatedTags = {...document.tags}..removeAll(tagsToRemove);
    await _documentRepository.update(
      document.copyWith(
        tags: updatedTags,
        overwriteTags: true,
      ),
    );
    emit(
      InboxState(
        isLoaded: true,
        inboxTags: state.inboxTags,
        inboxItems: state.inboxItems.where((doc) => doc.id != document.id),
      ),
    );

    return tagsToRemove;
  }

  Future<void> undoRemove(
      DocumentModel document, Iterable<int> removedTags) async {
    final updatedDoc = document.copyWith(
      tags: {...document.tags, ...removedTags},
      overwriteTags: true,
    );
    await _documentRepository.update(updatedDoc);
    emit(InboxState(
      isLoaded: true,
      inboxItems: [...state.inboxItems, updatedDoc]
        ..sort((d1, d2) => d1.added.compareTo(d2.added)),
      inboxTags: state.inboxTags,
    ));
  }

  ///
  /// Removes inbox tags from all documents in the inbox.
  ///
  Future<void> clearInbox() async {
    await _documentRepository.bulkAction(BulkModifyTagsAction.removeTags(
        state.inboxItems.map((e) => e.id), state.inboxTags));
    emit(
      InboxState(
        isLoaded: true,
        inboxTags: state.inboxTags,
      ),
    );
  }
}
