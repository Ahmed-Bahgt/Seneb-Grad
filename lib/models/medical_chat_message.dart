class PubMedSource {
  final String pmid;
  final String title;
  final String journal;
  final String year;
  final String link;

  const PubMedSource({
    required this.pmid,
    required this.title,
    required this.journal,
    required this.year,
    required this.link,
  });
}

class MedicalChatMessage {
  final String text;
  final bool isUser;
  final bool isLoading;
  final bool usedRag;
  final List<PubMedSource> ragSources;

  MedicalChatMessage({
    required this.text,
    required this.isUser,
    this.isLoading = false,
    this.usedRag = false,
    this.ragSources = const [],
  });
}
