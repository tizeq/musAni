import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musani/library/library_controller.dart';
import 'package:musani/library/library_repository.dart';
import 'package:musani/library/models.dart';

import 'support/library_fakes.dart';

class PendingLibraryRepository extends LibraryRepository {
  PendingLibraryRepository() : super('/tmp/unused-controller-test');
  final requests = <String, Completer<LibraryResult>>{};

  @override
  Future<LibraryResult> query(LibraryQuery query) =>
      (requests[query.search] = Completer<LibraryResult>()).future;
}

void main() {
  test(
    'returning to a section reloads its saved query after a catalog edit',
    () async {
      final tracks = sampleLibraryTracks('/tmp');
      final repository = FakeLibraryRepository(tracks);
      final controller = LibraryController(repository);
      const query = LibraryQuery(
        view: LibraryView.tracks,
        search: 'saved tracks',
      );
      await controller.search(query);
      await controller.search(const LibraryQuery());
      await controller.search(
        controller.queryFor(LibraryView.tracks),
        restoreSection: true,
      );
      expect(repository.queries, hasLength(2));

      await controller.search(const LibraryQuery(), restoreSection: true);
      await controller.metadataChanged(tracks.first.path);
      await controller.search(
        controller.queryFor(LibraryView.tracks),
        restoreSection: true,
      );
      expect(repository.queries, hasLength(4));
      expect(repository.queries.last.criteria, query.criteria);
      controller.dispose();
    },
  );

  test('a slow old search cannot overwrite a newer result', () async {
    final repository = PendingLibraryRepository();
    final controller = LibraryController(repository);
    final slow = controller.search(const LibraryQuery(search: 'old'));
    final fast = controller.search(const LibraryQuery(search: 'new'));
    repository.requests['new']!.complete(const LibraryResult(total: 2));
    await fast;
    repository.requests['old']!.complete(const LibraryResult(total: 100));
    await slow;
    expect(controller.query.search, 'new');
    expect(controller.result.total, 2);
    expect(controller.loading, isFalse);
    controller.dispose();
  });

  test('errors are visible and a subsequent search recovers', () async {
    final repository = PendingLibraryRepository();
    final controller = LibraryController(repository);
    final failed = controller.search(const LibraryQuery(search: 'failure'));
    repository.requests['failure']!.completeError(
      StateError('database unavailable'),
    );
    await failed;
    expect(controller.error, contains('database unavailable'));
    final recovered = controller.search(
      const LibraryQuery(search: 'recovered'),
    );
    repository.requests['recovered']!.complete(const LibraryResult(total: 0));
    await recovered;
    expect(controller.error, isNull);
    controller.dispose();
  });

  test(
    'finishing a request after widget disposal does not notify listeners',
    () async {
      final repository = PendingLibraryRepository();
      final controller = LibraryController(repository);
      final pending = controller.search(const LibraryQuery());
      controller.dispose();
      repository.requests['']!.complete(const LibraryResult(total: 1));
      await pending;
    },
  );
}
