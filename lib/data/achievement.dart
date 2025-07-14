// lib/data/achievement.dart

class Achievement {
  final String id;
  final String title;
  final String description;
  final String asset; // path to the badge image in assets/
  bool unlocked;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.asset,
    this.unlocked = false,
  });
}
