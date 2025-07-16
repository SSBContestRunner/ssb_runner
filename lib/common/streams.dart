Stream<T> flattenStreams<T>(Stream<Stream<T>> source) async* {
  await for (var stream in source) {
    yield* stream;
  }
}
