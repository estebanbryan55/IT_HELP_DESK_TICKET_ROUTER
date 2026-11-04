import 'dart:convert';
import 'dart:io';

import 'models.dart';

class RoutingDecision {
  final String category;
  final String priority;

  /// Null means no team could be decided and a supervisor must triage the ticket.
  final String? team;
  final String reason;

  RoutingDecision({required this.category, required this.priority, required this.team, required this.reason});
}

/// Rule-based categorisation. Rules live in config/routing_rules.json so support staff
/// can tune keywords without a code change.
class RoutingRules {
  final Map<String, ({String team, List<String> keywords})> categories;
  final Map<String, List<String>> priorityRaise;

  RoutingRules({required this.categories, required this.priorityRaise});

  factory RoutingRules.fromJson(Map<String, dynamic> j) => RoutingRules(
        categories: {
          for (final e in (j['categories'] as Map<String, dynamic>).entries)
            e.key: (
              team: e.value['team'] as String,
              keywords: [for (final k in e.value['keywords'] as List) (k as String).toLowerCase()],
            ),
        },
        priorityRaise: {
          for (final e in (j['priorityRaise'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: [for (final k in e.value as List) (k as String).toLowerCase()],
        },
      );

  static RoutingRules load(String path) => RoutingRules.fromJson(jsonDecode(File(path).readAsStringSync()));

  String? teamFor(String category) => categories[category]?.team;

  RoutingDecision decide({
    required String title,
    required String description,
    required String requestedCategory,
    required String requestedPriority,
  }) {
    final text = '$title $description'.toLowerCase();
    final reasons = <String>[];

    // 1. Category: requester's explicit choice wins; otherwise keyword scoring.
    String category;
    if (requestedCategory != 'auto' && requestedCategory != 'other') {
      category = requestedCategory;
      reasons.add('category chosen by requester');
    } else {
      final scores = <String, int>{
        for (final e in categories.entries) e.key: e.value.keywords.where(text.contains).length,
      };
      final best = scores.values.fold(0, (a, b) => a > b ? a : b);
      final leaders = [for (final e in scores.entries) if (e.value == best && best > 0) e.key];
      if (leaders.length == 1) {
        category = leaders.single;
        reasons.add('keyword match: $category ($best hit${best == 1 ? '' : 's'})');
      } else if (leaders.isEmpty) {
        category = 'other';
        reasons.add('no keyword matched');
      } else {
        category = 'other';
        reasons.add('ambiguous keywords: ${leaders.join(', ')}');
      }
    }

    // 2. Priority: rules may raise, never lower, the requester's priority.
    var priority = requestedPriority;
    for (final level in ['critical', 'high']) {
      final words = priorityRaise[level] ?? const [];
      final hit = words.where(text.contains).firstOrNull;
      if (hit != null && Priorities.rank(level) > Priorities.rank(priority)) {
        reasons.add('priority raised $priority -> $level by keyword "$hit"');
        priority = level;
        break;
      }
    }

    return RoutingDecision(category: category, priority: priority, team: teamFor(category), reason: reasons.join('; '));
  }
}
