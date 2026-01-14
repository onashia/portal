class ApiResult<T> {
  const ApiResult.success(this.data)
    : error = null,
      stackTrace = null,
      isSuccess = true;

  const ApiResult.error(this.error, [this.stackTrace])
    : data = null,
      isSuccess = false;

  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final bool isSuccess;
}
