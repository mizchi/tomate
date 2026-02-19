// Core enums

///|
pub(all) enum Status {
  Pending
  InProgress
  Complete
  Aborted
  Blocked
  Error
} derive(Eq, Show, Hash)

///|
pub(all) enum RuleMatchMethod {
  TagDetect
  AiJudge
  AiJudgeFallback
  Aggregate
  AutoSelect
} derive(Eq, Show)

///|
pub(all) enum PermissionMode {
  Readonly
  Edit
  Full
} derive(Eq, Show)

///|
pub(all) enum ProviderType {
  Claude
  Mock
} derive(Eq, Show)

///|
pub(all) enum PhaseName {
  Execute
  Report
  Judge
} derive(Eq, Show)

///|
pub(all) enum AggregateType {
  All
  Any
} derive(Eq, Show)

///|
pub(all) enum LoopAction {
  Abort
  Warn
  Ignore
} derive(Eq, Show)

///|
pub(all) enum PieceStatus {
  Running
  Completed
  PieceAborted
} derive(Eq, Show)

// Core structs

///|
pub(all) struct AgentResponse {
  persona : String
  status : Status
  content : String
  error : String?
  matched_rule_index : Int?
  matched_rule_method : RuleMatchMethod?
} derive(Show)

///|
pub(all) struct PieceRule {
  condition : String
  next : String?
  is_ai_condition : Bool
  ai_condition_text : String?
  is_aggregate_condition : Bool
  aggregate_type : AggregateType?
  aggregate_condition_text : Array[String]?
} derive(Show)

///|
pub(all) struct OutputContract {
  name : String
  format : String
  use_judge : Bool
  order : String?
} derive(Show)

///|
pub(all) struct PieceMovement {
  name : String
  description : String?
  persona : String?
  persona_display_name : String
  allowed_tools : Array[String]?
  provider : ProviderType?
  model : String?
  required_permission_mode : PermissionMode?
  edit : Bool
  instruction_template : String
  rules : Array[PieceRule]
  output_contracts : Array[OutputContract]
  pass_previous_response : Bool
  parallel : Array[PieceMovement]?
  arpeggio : ArpeggioConfig?
  team_leader : TeamLeaderConfig?
  policy_contents : Array[String]?
  knowledge_contents : Array[String]?
} derive(Show)

///|
pub(all) struct PieceConfig {
  name : String
  description : String?
  movements : Array[PieceMovement]
  initial_movement : String
  max_movements : Int
  loop_detection : LoopDetectionConfig?
  loop_monitors : Array[LoopMonitorConfig]?
} derive(Show)

// Arpeggio types (TODO: stub)

///|
pub(all) struct ArpeggioMergeConfig {
  strategy : String // "concat" | "custom"
  separator : String?
} derive(Show)

///|
pub(all) struct ArpeggioConfig {
  source : String
  source_path : String
  batch_size : Int
  template_path : String
  merge : ArpeggioMergeConfig
  max_retries : Int
  output_path : String?
} derive(Show)

// Loop detection types

///|
pub(all) struct LoopDetectionConfig {
  max_consecutive_same_step : Int
  action : LoopAction
} derive(Show)

///|
pub(all) struct LoopMonitorRule {
  condition : String
  next : String
} derive(Show)

///|
pub(all) struct LoopMonitorJudge {
  persona : String?
  instruction_template : String?
  rules : Array[LoopMonitorRule]
} derive(Show)

///|
pub(all) struct LoopMonitorConfig {
  cycle : Array[String]
  threshold : Int
  judge : LoopMonitorJudge
} derive(Show)

// Team leader types (TODO: stub)

///|
pub(all) struct TeamLeaderConfig {
  persona : String?
  max_parts : Int
  timeout_ms : Int
  part_persona : String?
  part_allowed_tools : Array[String]?
  part_edit : Bool
  part_permission_mode : PermissionMode?
} derive(Show)

// State types

///|
pub(all) struct PieceState {
  mut piece_name : String
  mut current_movement : String
  mut iteration : Int
  movement_outputs : Map[String, AgentResponse]
  mut last_output : AgentResponse?
  user_inputs : Array[String]
  persona_sessions : Map[String, String]
  movement_iterations : Map[String, Int]
  mut status : PieceStatus
} derive(Show)

// Faceted prompt types

///|
pub(all) struct FacetSet {
  persona : String?
  policies : Array[String]
  knowledge : Array[String]
  instructions : Array[String]
} derive(Show)

///|
pub(all) struct ComposedPrompt {
  system_prompt : String
  user_message : String
} derive(Show)

// Engine callbacks (replaces EventEmitter)

///|
pub(all) struct EngineCallbacks {
  on_movement_start : (String, Int, String) -> Unit // (movement_name, iteration, instruction)
  on_movement_complete : (String, AgentResponse, String) -> Unit // (movement_name, response, instruction)
  on_movement_report : (String, String, String) -> Unit // (movement_name, file_path, file_name)
  on_phase_start : (String, PhaseName, String) -> Unit // (movement_name, phase, instruction)
  on_phase_complete : (String, PhaseName, String, String) -> Unit // (movement_name, phase, content, status)
  on_piece_complete : (PieceState) -> Unit
  on_piece_abort : (PieceState, String) -> Unit // (state, reason)
  on_iteration_limit : (Int, Int) -> Unit // (iteration, max_movements)
  on_loop_detected : (String, Int) -> Unit // (movement_name, consecutive_count)
  on_cycle_detected : (Array[String], Int) -> Unit // (cycle, cycle_count)
}

///|
pub fn EngineCallbacks::noop() -> EngineCallbacks {
  {
    on_movement_start: fn(_name, _iter, _instr) {  },
    on_movement_complete: fn(_name, _resp, _instr) {  },
    on_movement_report: fn(_name, _path, _fname) {  },
    on_phase_start: fn(_name, _phase, _instr) {  },
    on_phase_complete: fn(_name, _phase, _content, _status) {  },
    on_piece_complete: fn(_state) {  },
    on_piece_abort: fn(_state, _reason) {  },
    on_iteration_limit: fn(_iter, _max) {  },
    on_loop_detected: fn(_name, _count) {  },
    on_cycle_detected: fn(_cycle, _count) {  },
  }
}

// PieceConfig methods

///|
pub fn PieceConfig::create_initial_state(self : PieceConfig) -> PieceState {
  {
    piece_name: self.name,
    current_movement: self.initial_movement,
    iteration: 0,
    movement_outputs: Map::new(),
    last_output: None,
    user_inputs: [],
    persona_sessions: Map::new(),
    movement_iterations: Map::new(),
    status: PieceStatus::Running,
  }
}

///|
pub fn PieceConfig::find_movement(
  self : PieceConfig,
  name : String,
) -> PieceMovement? {
  for m in self.movements {
    if m.name == name {
      return Some(m)
    }
  }
  None
}

// PieceState methods

///|
pub fn PieceState::increment_iteration(self : PieceState) -> Unit {
  self.iteration += 1
}

///|
pub fn PieceState::increment_movement_iteration(
  self : PieceState,
  movement_name : String,
) -> Int {
  let current = self.movement_iterations.get(movement_name).unwrap_or(0)
  let next = current + 1
  self.movement_iterations[movement_name] = next
  next
}

///|
pub fn PieceState::record_output(
  self : PieceState,
  movement_name : String,
  response : AgentResponse,
) -> Unit {
  self.movement_outputs[movement_name] = response
  self.last_output = Some(response)
}

///|
pub fn PieceState::transition_to(
  self : PieceState,
  next_movement : String,
) -> Unit {
  self.current_movement = next_movement
}

///|
pub fn PieceState::complete(self : PieceState) -> Unit {
  self.status = PieceStatus::Completed
}

///|
pub fn PieceState::abort(self : PieceState) -> Unit {
  self.status = PieceStatus::PieceAborted
}

///|
pub fn PieceState::is_running(self : PieceState) -> Bool {
  self.status == PieceStatus::Running
}

///|
pub fn PieceState::get_last_output_content(self : PieceState) -> String? {
  match self.last_output {
    Some(resp) => Some(resp.content)
    None => None
  }
}

