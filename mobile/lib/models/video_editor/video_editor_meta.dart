class VideoEditorMeta {
  VideoEditorMeta({
    required this.title,
    required this.description,
    required this.hashtags,
    this.allowAudioReuse = false,
    this.expireTime,
  });

  final String title;
  final String description;
  final List<String> hashtags;
  final bool allowAudioReuse;
  final Duration? expireTime;

  VideoEditorMeta copyWith({
    String? title,
    String? description,
    List<String>? hashtags,
    bool? allowAudioReuse,
    Duration? expireTime,
  }) {
    return VideoEditorMeta(
      title: title ?? this.title,
      description: description ?? this.description,
      hashtags: hashtags ?? this.hashtags,
      allowAudioReuse: allowAudioReuse ?? this.allowAudioReuse,
      expireTime: expireTime ?? this.expireTime,
    );
  }
}
