/// Content models. The hierarchy is Grade → Subject → Unit → Lesson →
/// Questions, with Books and Exams hanging off the subject. Everything is
/// parsed from JSON "packs" (one per grade) so content can be edited on the
/// server and pulled by the app without a release.
library;

enum Stage {
  lowerBasic,
  upperBasic,
  secondary;

  static Stage parse(String value) => Stage.values.firstWhere((s) => s.name == value, orElse: () => Stage.upperBasic);
}

class StageInfo {
  const StageInfo({required this.stage, required this.name, required this.hint});

  factory StageInfo.fromJson(Map<String, dynamic> json) =>
      StageInfo(stage: Stage.parse(json['id'] as String), name: json['name'] as String, hint: json['hint'] as String);

  final Stage stage;
  final String name;
  final String hint;
}

class SubjectInfo {
  const SubjectInfo({required this.id, required this.key, required this.name, required this.icon, required this.color});

  factory SubjectInfo.fromJson(Map<String, dynamic> json) => SubjectInfo(
    id: json['id'] as String,
    key: json['key'] as String,
    name: json['name'] as String,
    icon: json['icon'] as String,
    color: json['color'] as int,
  );

  final String id;
  final String key;
  final String name;
  final String icon;
  final int color;
}

class GradeInfo {
  const GradeInfo({
    required this.id,
    required this.number,
    required this.stage,
    required this.name,
    required this.subjects,
    this.stream,
  });

  factory GradeInfo.fromJson(Map<String, dynamic> json) => GradeInfo(
    id: json['id'] as String,
    number: json['number'] as int,
    stage: Stage.parse(json['stage'] as String),
    name: json['name'] as String,
    stream: json['stream'] as String?,
    subjects: [for (final s in json['subjects'] as List) SubjectInfo.fromJson(s as Map<String, dynamic>)],
  );

  final String id;
  final int number;
  final Stage stage;
  final String name;
  final String? stream;
  final List<SubjectInfo> subjects;

  String get fullName => stream == null ? name : '$name – $stream';
}

/// All grades and subjects. Small and bundled; packs carry the heavy content.
class Catalog {
  const Catalog({required this.stages, required this.grades, required this.bundledPacks});

  factory Catalog.fromJson(Map<String, dynamic> json) => Catalog(
    stages: [for (final s in json['stages'] as List) StageInfo.fromJson(s as Map<String, dynamic>)],
    grades: [for (final g in json['grades'] as List) GradeInfo.fromJson(g as Map<String, dynamic>)],
    bundledPacks: (json['bundledPacks'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
  );

  final List<StageInfo> stages;
  final List<GradeInfo> grades;

  /// Grade id → version of the pack shipped inside the app.
  final Map<String, int> bundledPacks;

  GradeInfo? grade(String id) {
    for (final g in grades) {
      if (g.id == id) return g;
    }
    return null;
  }

  List<GradeInfo> gradesOf(Stage stage) => grades.where((g) => g.stage == stage).toList();
}

enum QuestionType {
  mcq('اختيار من متعدد'),
  trueFalse('صح أم خطأ'),
  fill('أكمل الفراغ'),
  match('صِل'),
  short('إجابة قصيرة'),
  essay('سؤال مقالي'),
  numeric('مسألة');

  const QuestionType(this.label);

  final String label;

  static QuestionType parse(String value) => QuestionType.values.firstWhere((t) => t.name == value);

  /// Essays need a human; everything else is graded on the device.
  bool get autoGraded => this != QuestionType.essay;
}

enum Difficulty {
  easy('سهل'),
  medium('متوسط'),
  hard('صعب'),
  advanced('متقدم');

  const Difficulty(this.label);

  final String label;

  int get level => index + 1;

  static Difficulty fromLevel(int level) => Difficulty.values[(level - 1).clamp(0, Difficulty.values.length - 1)];
}

class Question {
  const Question({
    required this.id,
    required this.type,
    required this.difficulty,
    required this.prompt,
    required this.lessonId,
    required this.subjectId,
    this.options = const [],
    this.answer,
    this.accepted = const [],
    this.pairs = const [],
    this.tolerance = 0.001,
    this.unit,
    this.explanation,
    this.modelAnswer,
    this.image,
  });

  factory Question.fromJson(Map<String, dynamic> json, {required String lessonId, required String subjectId}) =>
      Question(
        id: json['id'] as String,
        type: QuestionType.parse(json['type'] as String),
        difficulty: Difficulty.fromLevel(json['difficulty'] as int? ?? 1),
        prompt: json['prompt'] as String,
        lessonId: lessonId,
        subjectId: subjectId,
        options: [for (final o in json['options'] as List? ?? const []) o as String],
        answer: json['answer'],
        accepted: [for (final a in json['accepted'] as List? ?? const []) a as String],
        pairs: [
          for (final p in json['pairs'] as List? ?? const []) (left: (p as List)[0] as String, right: p[1] as String),
        ],
        tolerance: (json['tolerance'] as num?)?.toDouble() ?? 0.001,
        unit: json['unit'] as String?,
        explanation: json['explanation'] as String?,
        modelAnswer: json['modelAnswer'] as String?,
        image: json['image'] as String?,
      );

  final String id;
  final QuestionType type;
  final Difficulty difficulty;
  final String prompt;
  final String lessonId;
  final String subjectId;

  /// mcq choices.
  final List<String> options;

  /// mcq: option index (int); trueFalse: bool; numeric: num.
  final Object? answer;

  /// fill / short: accepted answers (compared after Arabic normalization).
  final List<String> accepted;

  /// match: correct left → right pairs.
  final List<({String left, String right})> pairs;
  final double tolerance;
  final String? unit;
  final String? explanation;
  final String? modelAnswer;

  /// `images/x.png` (bundled asset) or an https URL.
  final String? image;

  /// Human-readable correct answer, shown in results.
  String get correctAnswerText => switch (type) {
    QuestionType.mcq => options[answer as int],
    QuestionType.trueFalse => answer == true ? 'صح' : 'خطأ',
    QuestionType.fill || QuestionType.short => accepted.first,
    QuestionType.numeric => '${_formatNum(answer as num)}${unit == null ? '' : ' $unit'}',
    QuestionType.match => pairs.map((p) => '${p.left} ← ${p.right}').join('، '),
    QuestionType.essay => modelAnswer ?? '',
  };

  static String _formatNum(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}

class Lesson {
  const Lesson({
    required this.id,
    required this.unitId,
    required this.subjectId,
    required this.title,
    required this.objectives,
    required this.explanation,
    required this.examples,
    required this.keyPoints,
    required this.summary,
    required this.questions,
    this.videoUrl,
    this.bookPage,
  });

  factory Lesson.fromJson(Map<String, dynamic> json, {required String subjectId}) {
    final id = json['id'] as String;
    return Lesson(
      id: id,
      unitId: json['unitId'] as String,
      subjectId: subjectId,
      title: json['title'] as String,
      objectives: _strings(json['objectives']),
      explanation: json['explanation'] as String? ?? '',
      examples: _strings(json['examples']),
      keyPoints: _strings(json['keyPoints']),
      summary: json['summary'] as String? ?? '',
      videoUrl: json['videoUrl'] as String?,
      bookPage: json['bookPage'] as int?,
      questions: [
        for (final q in json['questions'] as List? ?? const [])
          Question.fromJson(q as Map<String, dynamic>, lessonId: id, subjectId: subjectId),
      ],
    );
  }

  final String id;
  final String unitId;
  final String subjectId;
  final String title;
  final List<String> objectives;
  final String explanation;
  final List<String> examples;
  final List<String> keyPoints;
  final String summary;
  final String? videoUrl;
  final int? bookPage;
  final List<Question> questions;

  /// Text used for search and for grounding the AI tutor.
  String get fullText => [title, ...objectives, explanation, ...examples, ...keyPoints, summary].join('\n');
}

class Unit {
  const Unit({required this.id, required this.semester, required this.title, required this.lessons});

  factory Unit.fromJson(Map<String, dynamic> json, {required String subjectId}) => Unit(
    id: json['id'] as String,
    semester: json['semester'] as int? ?? 1,
    title: json['title'] as String,
    lessons: [
      for (final l in json['lessons'] as List) Lesson.fromJson(l as Map<String, dynamic>, subjectId: subjectId),
    ],
  );

  final String id;
  final int semester;
  final String title;
  final List<Lesson> lessons;
}

class BookPage {
  const BookPage({required this.number, required this.text, this.lessonId});

  final int number;
  final String text;
  final String? lessonId;
}

class Book {
  const Book({required this.id, required this.subjectId, required this.title, required this.pages, this.pdfUrl});

  factory Book.fromJson(Map<String, dynamic> json, {required String subjectId}) => Book(
    id: json['id'] as String,
    subjectId: subjectId,
    title: json['title'] as String,
    pdfUrl: json['pdfUrl'] as String?,
    pages: [
      for (final p in json['pages'] as List)
        BookPage(
          number: (p as Map<String, dynamic>)['number'] as int,
          text: p['text'] as String,
          lessonId: p['lessonId'] as String?,
        ),
    ],
  );

  final String id;
  final String subjectId;
  final String title;
  final String? pdfUrl;
  final List<BookPage> pages;
}

class Exam {
  const Exam({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.durationMinutes,
    required this.questionCount,
    this.questionIds,
  });

  factory Exam.fromJson(Map<String, dynamic> json, {required String subjectId}) => Exam(
    id: json['id'] as String,
    subjectId: subjectId,
    title: json['title'] as String,
    durationMinutes: json['durationMinutes'] as int? ?? 30,
    questionCount: json['questionCount'] as int? ?? 10,
    questionIds: (json['questionIds'] as List?)?.cast<String>(),
  );

  final String id;
  final String subjectId;
  final String title;
  final int durationMinutes;
  final int questionCount;

  /// Fixed paper; null means "draw from the subject's question bank".
  final List<String>? questionIds;
}

class SubjectContent {
  const SubjectContent({required this.id, required this.books, required this.units, required this.exams});

  factory SubjectContent.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return SubjectContent(
      id: id,
      books: [
        for (final b in json['books'] as List? ?? const []) Book.fromJson(b as Map<String, dynamic>, subjectId: id),
      ],
      units: [
        for (final u in json['units'] as List? ?? const []) Unit.fromJson(u as Map<String, dynamic>, subjectId: id),
      ],
      exams: [
        for (final e in json['exams'] as List? ?? const []) Exam.fromJson(e as Map<String, dynamic>, subjectId: id),
      ],
    );
  }

  final String id;
  final List<Book> books;
  final List<Unit> units;
  final List<Exam> exams;

  Iterable<Lesson> get lessons => units.expand((u) => u.lessons);

  Iterable<Question> get questions => lessons.expand((l) => l.questions);
}

/// The full offline content of one grade, with lookup indices.
class GradePack {
  GradePack({required this.gradeId, required this.version, required this.subjects, this.demo = false}) {
    for (final s in subjects.values) {
      for (final u in s.units) {
        _units[u.id] = u;
        for (final l in u.lessons) {
          _lessons[l.id] = l;
          for (final q in l.questions) {
            _questions[q.id] = q;
          }
        }
      }
      for (final b in s.books) {
        _books[b.id] = b;
      }
      for (final e in s.exams) {
        _exams[e.id] = e;
      }
    }
  }

  factory GradePack.fromJson(Map<String, dynamic> json) => GradePack(
    gradeId: json['gradeId'] as String,
    version: json['version'] as int,
    demo: json['demo'] as bool? ?? false,
    subjects: {
      for (final s in json['subjects'] as List) (s as Map<String, dynamic>)['id'] as String: SubjectContent.fromJson(s),
    },
  );

  final String gradeId;
  final int version;
  final bool demo;
  final Map<String, SubjectContent> subjects;

  final _units = <String, Unit>{};
  final _lessons = <String, Lesson>{};
  final _questions = <String, Question>{};
  final _books = <String, Book>{};
  final _exams = <String, Exam>{};

  Unit? unit(String id) => _units[id];
  Lesson? lesson(String id) => _lessons[id];
  Question? question(String id) => _questions[id];
  Book? book(String id) => _books[id];
  Exam? exam(String id) => _exams[id];

  Iterable<Lesson> get lessons => _lessons.values;
  Iterable<Question> get questions => _questions.values;
  Iterable<Exam> get exams => _exams.values;
  Iterable<Book> get books => _books.values;
}

List<String> _strings(Object? value) => [for (final v in value as List? ?? const []) v as String];
