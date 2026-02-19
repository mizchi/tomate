// Config: JSON parsing and Builder DSL for PieceConfig

///|
suberror ConfigError {
  ParseError(String)
  MissingField(String)
  InvalidValue(String)
} derive(Show)

// JSON parsing helpers

///|
fn get_string(
  obj : Map[String, Json],
  key : String,
) -> String raise ConfigError {
  match obj.get(key) {
    Some(Json::String(s)) => s
    Some(_) => raise ConfigError::InvalidValue("\{key} must be a string")
    None => raise ConfigError::MissingField(key)
  }
}

///|
fn get_string_opt(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
}

///|
fn get_int(obj : Map[String, Json], key : String, default : Int) -> Int {
  match obj.get(key) {
    Some(Json::Number(n, ..)) => n.to_int()
    _ => default
  }
}

///|
fn get_bool(obj : Map[String, Json], key : String, default : Bool) -> Bool {
  match obj.get(key) {
    Some(Json::True) => true
    Some(Json::False) => false
    _ => default
  }
}

///|
fn get_string_array(obj : Map[String, Json], key : String) -> Array[String]? {
  match obj.get(key) {
    Some(Json::Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        match item {
          Json::String(s) => result.push(s)
          _ => ()
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn get_object(obj : Map[String, Json], key : String) -> Map[String, Json]? {
  match obj.get(key) {
    Some(Json::Object(o)) => Some(o)
    _ => None
  }
}

// Parse PieceRule from JSON

///|
fn parse_rule(json : Json) -> @types.PieceRule raise ConfigError {
  match json {
    Json::Object(obj) => {
      let condition = get_string(obj, "condition")
      {
        condition,
        next: get_string_opt(obj, "next"),
        is_ai_condition: get_bool(obj, "isAiCondition", false),
        ai_condition_text: get_string_opt(obj, "aiConditionText"),
        is_aggregate_condition: get_bool(obj, "isAggregateCondition", false),
        aggregate_type: match get_string_opt(obj, "aggregateType") {
          Some("all") => Some(@types.AggregateType::All)
          Some("any") => Some(@types.AggregateType::Any)
          _ => None
        },
        aggregate_condition_text: get_string_array(
          obj, "aggregateConditionText",
        ),
      }
    }
    _ => raise ConfigError::ParseError("Rule must be an object")
  }
}

// Parse OutputContract from JSON

///|
fn parse_output_contract(
  json : Json,
) -> @types.OutputContract raise ConfigError {
  match json {
    Json::Object(obj) => {
      let name = get_string(obj, "name")
      let format = get_string(obj, "format")
      {
        name,
        format,
        use_judge: get_bool(obj, "useJudge", true),
        order: get_string_opt(obj, "order"),
      }
    }
    _ => raise ConfigError::ParseError("OutputContract must be an object")
  }
}

// Parse PieceMovement from JSON

///|
fn parse_movement(json : Json) -> @types.PieceMovement raise ConfigError {
  match json {
    Json::Object(obj) => {
      let name = get_string(obj, "name")
      let rules : Array[@types.PieceRule] = []
      match obj.get("rules") {
        Some(Json::Array(arr)) =>
          for r in arr {
            rules.push(parse_rule(r))
          }
        _ => ()
      }
      let output_contracts : Array[@types.OutputContract] = []
      match obj.get("outputContracts") {
        Some(Json::Array(arr)) =>
          for oc in arr {
            output_contracts.push(parse_output_contract(oc))
          }
        _ => ()
      }
      {
        name,
        description: get_string_opt(obj, "description"),
        persona: get_string_opt(obj, "persona"),
        persona_display_name: get_string_opt(obj, "personaDisplayName").unwrap_or(
          name,
        ),
        allowed_tools: get_string_array(obj, "allowedTools"),
        provider: match get_string_opt(obj, "provider") {
          Some("claude") => Some(@types.ProviderType::Claude)
          Some("mock") => Some(@types.ProviderType::Mock)
          _ => None
        },
        model: get_string_opt(obj, "model"),
        required_permission_mode: match
          get_string_opt(obj, "requiredPermissionMode") {
          Some("readonly") => Some(@types.PermissionMode::Readonly)
          Some("edit") => Some(@types.PermissionMode::Edit)
          Some("full") => Some(@types.PermissionMode::Full)
          _ => None
        },
        edit: get_bool(obj, "edit", false),
        instruction_template: get_string_opt(obj, "instructionTemplate").unwrap_or(
          "",
        ),
        rules,
        output_contracts,
        pass_previous_response: get_bool(obj, "passPreviousResponse", false),
        parallel: match obj.get("parallel") {
          Some(Json::Array(arr)) => {
            let subs : Array[@types.PieceMovement] = []
            for item in arr {
              subs.push(parse_movement(item))
            }
            Some(subs)
          }
          _ => None
        },
        arpeggio: None,
        team_leader: None,
        policy_contents: get_string_array(obj, "policyContents"),
        knowledge_contents: get_string_array(obj, "knowledgeContents"),
      }
    }
    _ => raise ConfigError::ParseError("Movement must be an object")
  }
}

// Parse LoopDetectionConfig

///|
fn parse_loop_detection(obj : Map[String, Json]) -> @types.LoopDetectionConfig {
  {
    max_consecutive_same_step: get_int(obj, "maxConsecutiveSameStep", 10),
    action: match get_string_opt(obj, "action") {
      Some("abort") => @types.LoopAction::Abort
      Some("ignore") => @types.LoopAction::Ignore
      _ => @types.LoopAction::Warn
    },
  }
}

// Parse LoopMonitorConfig

///|
fn parse_loop_monitor(
  json : Json,
) -> @types.LoopMonitorConfig raise ConfigError {
  match json {
    Json::Object(obj) => {
      let cycle = get_string_array(obj, "cycle").unwrap_or([])
      let threshold = get_int(obj, "threshold", 3)
      let judge_rules : Array[@types.LoopMonitorRule] = []
      match get_object(obj, "judge") {
        Some(judge_obj) =>
          match judge_obj.get("rules") {
            Some(Json::Array(arr)) =>
              for r in arr {
                match r {
                  Json::Object(ro) =>
                    judge_rules.push({
                      condition: get_string_opt(ro, "condition").unwrap_or(""),
                      next: get_string_opt(ro, "next").unwrap_or(""),
                    })
                  _ => ()
                }
              }
            _ => ()
          }
        None => ()
      }
      {
        cycle,
        threshold,
        judge: {
          persona: match get_object(obj, "judge") {
            Some(j) => get_string_opt(j, "persona")
            None => None
          },
          instruction_template: match get_object(obj, "judge") {
            Some(j) => get_string_opt(j, "instructionTemplate")
            None => None
          },
          rules: judge_rules,
        },
      }
    }
    _ => raise ConfigError::ParseError("LoopMonitor must be an object")
  }
}

// Parse full PieceConfig from JSON string

///|
pub fn parse_piece_config(
  json_str : String,
) -> @types.PieceConfig raise ConfigError {
  let json = @json.parse(json_str) catch {
    e => raise ConfigError::ParseError("Invalid JSON: \{e}")
  }
  match json {
    Json::Object(obj) => {
      let name = get_string(obj, "name")
      let movements : Array[@types.PieceMovement] = []
      match obj.get("movements") {
        Some(Json::Array(arr)) =>
          for m in arr {
            movements.push(parse_movement(m))
          }
        _ => raise ConfigError::MissingField("movements")
      }
      let loop_monitors : Array[@types.LoopMonitorConfig] = []
      match obj.get("loopMonitors") {
        Some(Json::Array(arr)) =>
          for m in arr {
            loop_monitors.push(parse_loop_monitor(m))
          }
        _ => ()
      }
      {
        name,
        description: get_string_opt(obj, "description"),
        movements,
        initial_movement: get_string_opt(obj, "initialMovement").unwrap_or(
          if movements.length() > 0 {
            movements[0].name
          } else {
            ""
          },
        ),
        max_movements: get_int(obj, "maxMovements", 20),
        loop_detection: match get_object(obj, "loopDetection") {
          Some(ld) => Some(parse_loop_detection(ld))
          None => None
        },
        loop_monitors: if loop_monitors.length() > 0 {
          Some(loop_monitors)
        } else {
          None
        },
      }
    }
    _ => raise ConfigError::ParseError("Config must be a JSON object")
  }
}

// Builder DSL

///|
pub fn rule(
  condition : String,
  next? : String? = None,
  ai? : Bool = false,
) -> @types.PieceRule {
  {
    condition,
    next,
    is_ai_condition: ai,
    ai_condition_text: if ai {
      Some(condition)
    } else {
      None
    },
    is_aggregate_condition: false,
    aggregate_type: None,
    aggregate_condition_text: None,
  }
}

///|
pub fn movement(
  name : String,
  instruction? : String = "",
  persona? : String? = None,
  rules? : Array[@types.PieceRule] = [],
  edit? : Bool = false,
  pass_previous? : Bool = false,
) -> @types.PieceMovement {
  {
    name,
    description: None,
    persona,
    persona_display_name: name,
    allowed_tools: None,
    provider: None,
    model: None,
    required_permission_mode: None,
    edit,
    instruction_template: instruction,
    rules,
    output_contracts: [],
    pass_previous_response: pass_previous,
    parallel: None,
    arpeggio: None,
    team_leader: None,
    policy_contents: None,
    knowledge_contents: None,
  }
}

///|
pub fn piece(
  name : String,
  movements : Array[@types.PieceMovement],
  initial? : String? = None,
  max_movements? : Int = 20,
  loop_detection? : @types.LoopDetectionConfig? = None,
) -> @types.PieceConfig {
  {
    name,
    description: None,
    movements,
    initial_movement: match initial {
      Some(i) => i
      None => if movements.length() > 0 { movements[0].name } else { "" }
    },
    max_movements,
    loop_detection,
    loop_monitors: None,
  }
}
