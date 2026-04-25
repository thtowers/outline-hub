import 'dart:async';
import 'package:flutter/material.dart';

class SpeechSection {
  final String id;
  String title;
  Duration targetDuration;      // Original planned time
  Duration adjustedTargetDuration; // Planned time + carry-over from previous sections
  Duration elapsedDuration;    // Real time spent

  SpeechSection({
    required this.id,
    this.title = 'Nova Seção',
    this.targetDuration = Duration.zero,
    this.adjustedTargetDuration = Duration.zero,
    this.elapsedDuration = Duration.zero,
  });
}

class SpeechController extends ChangeNotifier {
  List<SpeechSection> _sections = [];
  Duration _totalSpeechTarget = Duration.zero;
  bool _isRunning = false;
  Timer? _timer;
  int _currentSectionIndex = 0;
  bool _isSessionFinished = false;
  
  // Stopwatch state
  Duration _totalElapsed = Duration.zero;
  
  List<SpeechSection> get sections => _sections;
  Duration get totalSpeechTarget => _totalSpeechTarget;
  bool get isRunning => _isRunning;
  Duration get totalElapsed => _totalElapsed;
  int get currentSectionIndex => _currentSectionIndex;
  bool get isSessionFinished => _isSessionFinished;

  void setTotalSpeechTarget(Duration duration) {
    _totalSpeechTarget = duration;
    _recalculateAdjustedTargets();
    notifyListeners();
  }

  void updateSections(List<String> sectionTitles) {
    List<SpeechSection> newSections = [];
    for (int i = 0; i < sectionTitles.length; i++) {
      final title = sectionTitles[i];
      final existing = _sections.length > i ? _sections[i] : null;
      
      newSections.add(SpeechSection(
        id: 'section_$i',
        title: title.isEmpty ? 'Seção ${i + 1}' : title,
        targetDuration: existing?.targetDuration ?? Duration.zero,
        adjustedTargetDuration: existing?.adjustedTargetDuration ?? Duration.zero,
        elapsedDuration: existing?.elapsedDuration ?? Duration.zero,
      ));
    }
    _sections = newSections;
    _recalculateAdjustedTargets();
    notifyListeners();
  }

  void updateTargetDuration(int index, Duration duration) {
    if (index >= 0 && index < _sections.length) {
      _sections[index].targetDuration = duration;
      _recalculateAdjustedTargets();
      notifyListeners();
    }
  }

  // The core logic: Carry over surplus or deficit to the next sections
  void _recalculateAdjustedTargets() {
    Duration carryOver = Duration.zero;
    for (int i = 0; i < _sections.length; i++) {
      // If the section is already finished or is the current one, 
      // we calculate how much time is left or was saved.
      if (i < _currentSectionIndex) {
        // Surplus/Deficit from finished sections
        carryOver += (_sections[i].targetDuration - _sections[i].elapsedDuration);
      } else if (i == _currentSectionIndex) {
        _sections[i].adjustedTargetDuration = _sections[i].targetDuration + carryOver;
      } else {
        // Future sections don't know their carry-over yet, 
        // but we can initialize them with original targets.
        _sections[i].adjustedTargetDuration = _sections[i].targetDuration;
      }
    }
  }

  void startTimer() {
    if (_isRunning) return;
    _isRunning = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _totalElapsed += const Duration(seconds: 1);
      
      if (_currentSectionIndex < _sections.length) {
        _sections[_currentSectionIndex].elapsedDuration += const Duration(seconds: 1);
      }
      
      notifyListeners();
    });
    notifyListeners();
  }

  void pauseTimer() {
    _isRunning = false;
    _timer?.cancel();
    notifyListeners();
  }

  void resetTimer() {
    pauseTimer();
    _totalElapsed = Duration.zero;
    for (var section in _sections) {
      section.elapsedDuration = Duration.zero;
    }
    _currentSectionIndex = 0;
    _isSessionFinished = false;
    _recalculateAdjustedTargets();
    notifyListeners();
  }

  void nextSection() {
    if (_currentSectionIndex < _sections.length - 1) {
      _currentSectionIndex++;
      _recalculateAdjustedTargets(); // Carry over logic kicks in here
      notifyListeners();
    }
  }

  void previousSection() {
    if (_currentSectionIndex > 0) {
      _currentSectionIndex--;
      _recalculateAdjustedTargets();
      notifyListeners();
    }
  }

  void restartCurrentSection() {
    if (_currentSectionIndex >= 0 && _currentSectionIndex < _sections.length) {
      _sections[_currentSectionIndex].elapsedDuration = Duration.zero;
      notifyListeners();
    }
  }

  void finishSession() {
    pauseTimer();
    _isSessionFinished = true;
    notifyListeners();
  }

  void renameSection(int index, String newTitle) {
    if (index >= 0 && index < _sections.length) {
      _sections[index].title = newTitle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
