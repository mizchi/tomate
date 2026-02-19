// LoopDetector: detects consecutive same-movement executions

///|
pub(all) struct LoopDetector {
  max_consecutive : Int
  action : @types.LoopAction
  mut last_movement : String?
  mut consecutive_count : Int
}

///|
pub fn LoopDetector::new(config : @types.LoopDetectionConfig) -> LoopDetector {
  {
    max_consecutive: config.max_consecutive_same_step,
    action: config.action,
    last_movement: None,
    consecutive_count: 0,
  }
}

///|
pub fn LoopDetector::default() -> LoopDetector {
  {
    max_consecutive: 10,
    action: @types.LoopAction::Warn,
    last_movement: None,
    consecutive_count: 0,
  }
}

///|
pub(all) enum LoopCheckResult {
  Ok
  Detected(Int) // consecutive count
} derive(Eq, Show)

///|
pub fn LoopDetector::record(
  self : LoopDetector,
  movement_name : String,
) -> LoopCheckResult {
  match self.last_movement {
    Some(last) if last == movement_name => {
      self.consecutive_count += 1
      if self.consecutive_count >= self.max_consecutive {
        LoopCheckResult::Detected(self.consecutive_count)
      } else {
        LoopCheckResult::Ok
      }
    }
    _ => {
      self.last_movement = Some(movement_name)
      self.consecutive_count = 1
      LoopCheckResult::Ok
    }
  }
}

///|
pub fn LoopDetector::reset(self : LoopDetector) -> Unit {
  self.last_movement = None
  self.consecutive_count = 0
}

// CycleDetector: detects multi-step cyclic patterns (e.g., review→fix→review→fix)

///|
pub(all) struct CycleDetector {
  cycle_pattern : Array[String]
  threshold : Int
  mut history : Array[String]
  mut cycle_count : Int
}

///|
pub fn CycleDetector::new(
  cycle_pattern : Array[String],
  threshold : Int,
) -> CycleDetector {
  { cycle_pattern, threshold, history: [], cycle_count: 0 }
}

///|
pub(all) enum CycleCheckResult {
  Ok
  CycleDetected(Int) // cycle count
} derive(Eq, Show)

///|
pub fn CycleDetector::record(
  self : CycleDetector,
  movement_name : String,
) -> CycleCheckResult {
  self.history.push(movement_name)
  let pattern_len = self.cycle_pattern.length()
  if pattern_len == 0 {
    return CycleCheckResult::Ok
  }
  // Check if the tail of history matches the cycle pattern
  let hist_len = self.history.length()
  if hist_len >= pattern_len {
    let mut matches = true
    for i in 0..<pattern_len {
      if self.history[hist_len - pattern_len + i] != self.cycle_pattern[i] {
        matches = false
        break
      }
    }
    if matches {
      self.cycle_count += 1
      if self.cycle_count >= self.threshold {
        return CycleCheckResult::CycleDetected(self.cycle_count)
      }
    }
  }
  CycleCheckResult::Ok
}

///|
pub fn CycleDetector::reset(self : CycleDetector) -> Unit {
  self.history = []
  self.cycle_count = 0
}

///|
pub fn CycleDetector::get_cycle_count(self : CycleDetector) -> Int {
  self.cycle_count
}
