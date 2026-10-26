const String defaultActionButtonTriggerInput = 'action_button_pressed';

String normalizeWorkflowTriggerInput(String? value) {
  final trimmed = value?.trim();
  return (trimmed == null || trimmed.isEmpty)
      ? defaultActionButtonTriggerInput
      : trimmed;
}
