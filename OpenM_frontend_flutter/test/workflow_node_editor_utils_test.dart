import 'package:openm/screens/admin/workflow_node_editor_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeWorkflowTriggerInput', () {
    test('defaults to action_button_pressed for empty values', () {
      expect(normalizeWorkflowTriggerInput(null), defaultActionButtonTriggerInput);
      expect(normalizeWorkflowTriggerInput(''), defaultActionButtonTriggerInput);
      expect(normalizeWorkflowTriggerInput('   '), defaultActionButtonTriggerInput);
    });

    test('preserves and trims existing values', () {
      expect(normalizeWorkflowTriggerInput('custom_trigger'), 'custom_trigger');
      expect(normalizeWorkflowTriggerInput('  custom_trigger  '), 'custom_trigger');
    });
  });
}
