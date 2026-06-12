import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('user workflow audit lists every workflow widget test file', () {
    final auditDoc = File('docs/user_workflow_test_audit.md');

    expect(
      auditDoc.existsSync(),
      isTrue,
      reason: 'The workflow audit document is the index for user workflow '
          'button and flow coverage.',
    );

    final auditMarkdown = auditDoc.readAsStringSync();
    final workflowTestFiles = Directory('test/widgets')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where(
          (name) =>
              name.startsWith('user_workflow_') && name.endsWith('_test.dart'),
        )
        .toList()
      ..sort();

    expect(workflowTestFiles, isNotEmpty);
    for (final fileName in workflowTestFiles) {
      expect(
        auditMarkdown,
        contains(fileName),
        reason: '$fileName must be represented in the workflow audit matrix.',
      );
    }

    expect(
      auditMarkdown,
      contains('## Residual Coverage Gaps'),
      reason: 'The audit must explicitly preserve remaining coverage gaps.',
    );
  });
}
