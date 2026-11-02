/// Missing metadata must remain absent rather than becoming the word "null".
String? normalizedBookDescription(String? value) {
  final text = value?.trim();
  if (text == null || text.isEmpty || text.toLowerCase() == 'null') return null;
  return text;
}
