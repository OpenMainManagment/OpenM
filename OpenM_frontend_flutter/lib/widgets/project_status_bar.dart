import 'package:flutter/material.dart';
import '../models/dtos.dart';

class ProjectStatusBar extends StatelessWidget {
  const ProjectStatusBar({
    super.key,
    required this.project,
    this.onNextStep,
    this.onPreviousStep,
    this.showNavigationButtons = false,
    this.isEditable = false,
  });

  final ProjectDto project;
  final VoidCallback? onNextStep;
  final VoidCallback? onPreviousStep;
  final bool showNavigationButtons;
  final bool isEditable;

  static const List<String> workflowStages = [
    'Quote',
    'Sale',
    'Construction',
    'Procurement',
    'Installation',
    'Programming',
    'Delivery',
    'Commissioning',
    'Final Acceptance',
    'Completed'
  ];

  @override
  Widget build(BuildContext context) {
    final currentStatusIndex = workflowStages.indexOf(project.status);
    if (currentStatusIndex < 0) {
      // Invalid status, return empty widget or default to quote
      return Container();
    }

    final progress = currentStatusIndex / (workflowStages.length - 1);

    return Column(
      children: [
        // Status bar with progress indicator
        Container(
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // Background (gray for future stages)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Progress fill (green for completed stages)
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: progress * MediaQuery.of(context).size.width,
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              // Stage indicators
              Row(
                children: [
                  for (int i = 0; i < workflowStages.length; i++)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < currentStatusIndex
                                ? Colors.green
                                : i == currentStatusIndex
                                    ? Colors.blue
                                    : Colors.grey[300],
                            border: Border.all(
                              color: i <= currentStatusIndex ? Colors.green : Colors.grey[400]!,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              workflowStages[i][0],
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        // Status text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Current Status: ${project.status}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        // Navigation buttons
        if (showNavigationButtons && isEditable)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: currentStatusIndex == 0 ? null : onPreviousStep,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous Step'),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: currentStatusIndex == workflowStages.length - 1
                      ? null
                      : onNextStep,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Next Step'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}