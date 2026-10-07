import '../../data/database.dart';
import '../../data/models.dart';
import '../quiz/quiz_engine.dart';

class AchievementBadge {
  const AchievementBadge(this.id, this.title, this.description, {required this.earned});

  final String id;
  final String title;
  final String description;
  final bool earned;
}

class SubjectStats {
  const SubjectStats({
    required this.subjectId,
    required this.totalLessons,
    required this.completedLessons,
    required this.mastery,
  });

  final String subjectId;
  final int totalLessons;
  final int completedLessons;
  final Mastery? mastery;

  double get completion => totalLessons == 0 ? 0 : completedLessons / totalLessons;
}

/// Suggested steps for a weak lesson: review → explanation → practice → retest.
class Recommendation {
  const Recommendation({required this.lesson, required this.mastery});

  final Lesson lesson;
  final Mastery mastery;
}

/// Everything the home, progress and (later) parent screens show, derived
/// from local records so it is always available offline.
class LearnerStats {
  const LearnerStats({
    required this.points,
    required this.level,
    required this.pointsIntoLevel,
    required this.pointsForNextLevel,
    required this.streak,
    required this.badges,
    required this.subjects,
    required this.lessonMastery,
    required this.completedLessons,
    required this.totalLessons,
    required this.attemptCount,
    required this.strengths,
    required this.weaknesses,
    required this.recommendations,
    required this.challengeDoneToday,
    required this.studyTime,
    required this.recentAccuracy,
    required this.previousAccuracy,
    this.lastLesson,
    this.nextLesson,
  });

  factory LearnerStats.compute({
    required GradePack? pack,
    required Map<String, LessonProgressRow> progress,
    required List<AttemptRecord> attempts,
    required List<AnswerRecord> answers,
    required Set<String> activityDays,
    required DateTime now,
  }) {
    final lessons = pack?.lessons.toList() ?? const <Lesson>[];
    final inPack = {for (final l in lessons) l.id};
    final completed = progress.values.where((p) => p.completed && inPack.contains(p.lessonId)).length;
    final lessonMastery = Mastery.byLesson(answers);
    final subjectMastery = Mastery.bySubject(answers);

    final correctPoints = answers.fold<double>(0, (s, a) => s + a.score) * 10;
    final passedExams = attempts.where((a) => a.kind == AttemptKind.exam && a.ratio >= 0.5).length;
    final challenges = attempts.where((a) => a.kind == AttemptKind.challenge).length;
    final points = correctPoints.round() + completed * 20 + passedExams * 50 + challenges * 30;

    // Level n starts at 50·n·(n−1) points: 0, 100, 300, 600, 1000, …
    var level = 1;
    while (points >= 50 * (level + 1) * level) {
      level++;
    }
    final levelStart = 50 * level * (level - 1);
    final levelEnd = 50 * (level + 1) * level;

    final today = ProgressRepository.dayKey(now);
    var streak = 0;
    var day = activityDays.contains(today) ? now : now.subtract(const Duration(days: 1));
    while (activityDays.contains(ProgressRepository.dayKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }

    final subjects = <SubjectStats>[
      for (final s in pack?.subjects.values ?? const <SubjectContent>[])
        SubjectStats(
          subjectId: s.id,
          totalLessons: s.lessons.length,
          completedLessons: s.lessons.where((l) => progress[l.id]?.completed ?? false).length,
          mastery: subjectMastery[s.id],
        ),
    ];

    final strengths = <Lesson>[];
    final weak = <Recommendation>[];
    for (final l in lessons) {
      final m = lessonMastery[l.id];
      if (m == null) continue;
      if (m.answered >= 3 && m.ratio >= 0.8) strengths.add(l);
      if (m.answered >= 2 && m.ratio < 0.6) weak.add(Recommendation(lesson: l, mastery: m));
    }
    weak.sort((a, b) => a.mastery.ratio.compareTo(b.mastery.ratio));

    Lesson? lastLesson;
    final opened = progress.values.where((p) => inPack.contains(p.lessonId)).toList()
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
    if (opened.isNotEmpty) lastLesson = pack!.lesson(opened.first.lessonId);
    final nextLesson = lessons.where((l) => !(progress[l.id]?.completed ?? false)).firstOrNull;

    final weekAgo = now.subtract(const Duration(days: 7));
    final twoWeeksAgo = now.subtract(const Duration(days: 14));
    double? avg(Iterable<AnswerRecord> list) =>
        list.isEmpty ? null : list.fold<double>(0, (s, a) => s + a.score) / list.length;

    final everCorrect = answers.where((a) => a.score == 1).length;
    final perfect = attempts.any((a) => a.maxScore >= 5 && a.score == a.maxScore);
    return LearnerStats(
      points: points,
      level: level,
      pointsIntoLevel: points - levelStart,
      pointsForNextLevel: levelEnd - levelStart,
      streak: streak,
      badges: [
        AchievementBadge('first_lesson', 'أول درس', 'أكملت أول درس', earned: completed >= 1),
        AchievementBadge('first_quiz', 'البداية', 'أنهيت أول اختبار', earned: attempts.isNotEmpty),
        AchievementBadge('streak3', 'مثابر', '3 أيام دراسة متتالية', earned: streak >= 3),
        AchievementBadge('streak7', 'أسبوع كامل', '7 أيام دراسة متتالية', earned: streak >= 7),
        AchievementBadge('perfect', 'العلامة الكاملة', 'علامة كاملة في اختبار من 5 أسئلة أو أكثر', earned: perfect),
        AchievementBadge('hundred', 'مئة إجابة', '100 إجابة صحيحة', earned: everCorrect >= 100),
        AchievementBadge('exam', 'جاهز للامتحان', 'نجحت في امتحان تجريبي', earned: passedExams > 0),
        AchievementBadge('challenger', 'متحدٍّ', 'أكملت 5 تحديات يومية', earned: challenges >= 5),
      ],
      subjects: subjects,
      lessonMastery: lessonMastery,
      completedLessons: completed,
      totalLessons: lessons.length,
      attemptCount: attempts.length,
      strengths: strengths,
      weaknesses: weak.map((r) => r.lesson).toList(),
      recommendations: weak.take(3).toList(),
      challengeDoneToday: attempts.any(
        (a) => a.kind == AttemptKind.challenge && ProgressRepository.dayKey(a.startedAt) == today,
      ),
      studyTime: attempts.fold(Duration.zero, (s, a) => s + a.duration),
      recentAccuracy: avg(answers.where((a) => a.answeredAt.isAfter(weekAgo))),
      previousAccuracy: avg(answers.where((a) => a.answeredAt.isAfter(twoWeeksAgo) && !a.answeredAt.isAfter(weekAgo))),
      lastLesson: lastLesson,
      nextLesson: nextLesson,
    );
  }

  final int points;
  final int level;
  final int pointsIntoLevel;
  final int pointsForNextLevel;
  final int streak;
  final List<AchievementBadge> badges;
  final List<SubjectStats> subjects;
  final Map<String, Mastery> lessonMastery;
  final int completedLessons;
  final int totalLessons;
  final int attemptCount;
  final List<Lesson> strengths;
  final List<Lesson> weaknesses;
  final List<Recommendation> recommendations;
  final bool challengeDoneToday;
  final Duration studyTime;

  /// Average score over the last 7 days and the 7 days before.
  final double? recentAccuracy;
  final double? previousAccuracy;
  final Lesson? lastLesson;
  final Lesson? nextLesson;

  double get completion => totalLessons == 0 ? 0 : completedLessons / totalLessons;

  /// Change vs. the previous week in percentage points, when both exist.
  int? get improvement =>
      recentAccuracy == null || previousAccuracy == null ? null : ((recentAccuracy! - previousAccuracy!) * 100).round();
}
