class Option {
  final String id;
  final String text;

  const Option({
    required this.id,
    required this.text,
  });
}

class Question {
  final String id;
  final String text;
  final List<Option> options;

  const Question({
    required this.id,
    required this.text,
    required this.options,
  });
}
