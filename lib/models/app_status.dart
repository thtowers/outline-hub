enum StatusType { ready, loading, success, error, info }

class AppStatus {
  final String message;
  final StatusType type;

  const AppStatus({
    required this.message,
    this.type = StatusType.ready,
  });

  factory AppStatus.ready() => const AppStatus(message: 'Pronto', type: StatusType.ready);
  factory AppStatus.loading(String msg) => AppStatus(message: msg, type: StatusType.loading);
  factory AppStatus.success(String msg) => AppStatus(message: msg, type: StatusType.success);
  factory AppStatus.error(String msg) => AppStatus(message: msg, type: StatusType.error);
  factory AppStatus.info(String msg) => AppStatus(message: msg, type: StatusType.info);
}
