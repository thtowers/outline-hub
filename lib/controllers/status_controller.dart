import 'package:flutter/foundation.dart';
import '../models/app_status.dart';

class StatusController extends ValueNotifier<AppStatus> {
  StatusController() : super(AppStatus.ready());

  void setReady() {
    value = AppStatus.ready();
  }

  void setLoading(String message) {
    value = AppStatus.loading(message);
  }

  void setSuccess(String message) {
    value = AppStatus.success(message);
  }

  void setError(String message) {
    value = AppStatus.error(message);
  }

  void setInfo(String message) {
    value = AppStatus.info(message);
  }
}
