abstract class UseCase<T, Params extends Object?> {
  Future<T> call([Params params]);
}


class NoParams extends Object {
  const NoParams();
}