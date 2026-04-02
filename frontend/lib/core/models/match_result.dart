class MatchResult {
  final int compatibilityScore;
  final List<String> strengths;
  final List<String> potentialFrictions;
  final String poeticSummary;

  MatchResult({
    required this.compatibilityScore,
    required this.strengths,
    required this.potentialFrictions,
    required this.poeticSummary,
  });

  factory MatchResult.fromJson(Map<String, dynamic> json) {
    return MatchResult(
      compatibilityScore: json['compatibility_score'],
      strengths: List<String>.from(json['strengths'] ?? []),
      potentialFrictions: List<String>.from(json['potential_frictions'] ?? []),
      poeticSummary: json['poetic_summary'],
    );
  }
}
