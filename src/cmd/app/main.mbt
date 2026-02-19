///|
let version = "0.1.0"

///|
fn main {
  let args = @sys.get_cli_args()[1:].to_array()
  match args {
    ["--version" | "-v", ..] => println(version)
    ["--help" | "-h", ..] => print_usage()
    ["run", .. rest] => run_workflow(rest.to_array())
    ["validate", .. rest] => validate_config(rest.to_array())
    ["debug", .. rest] => debug_provider(rest.to_array())
    [] => print_usage()
    _ => println("Unknown command. Use --help for usage.")
  }
}

///|
fn print_usage() -> Unit {
  let usage =
    #|Usage: tomate <command> [options]
    #|
    #|Commands:
    #|  run <config.json> --task "..."  Run a workflow
    #|  validate <config.json>          Validate config
    #|
    #|Options:
    #|  -h, --help                 Show this help message
    #|  -v, --version              Show version
    #|  --provider mock|claude     Provider type (default: claude)
    #|  --model <model>            Model name
    #|  --cwd <dir>                Working directory
  println(usage)
}

///|
fn parse_cli_options(
  args : Array[String],
) -> (String?, String?, String?, String?, String?) {
  // Returns: (config_path, task, provider, model, cwd)
  let mut config_path : String? = None
  let mut task : String? = None
  let mut provider_str : String? = None
  let mut model : String? = None
  let mut cwd : String? = None
  for i = 0; i < args.length(); {
    let arg = args[i]
    if arg == "--task" && i + 1 < args.length() {
      task = Some(args[i + 1])
      continue i + 2
    } else if arg == "--provider" && i + 1 < args.length() {
      provider_str = Some(args[i + 1])
      continue i + 2
    } else if arg == "--model" && i + 1 < args.length() {
      model = Some(args[i + 1])
      continue i + 2
    } else if arg == "--cwd" && i + 1 < args.length() {
      cwd = Some(args[i + 1])
      continue i + 2
    } else if config_path is None {
      config_path = Some(arg)
      continue i + 1
    } else {
      continue i + 1
    }
  }
  (config_path, task, provider_str, model, cwd)
}

///|
fn run_workflow(args : Array[String]) -> Unit {
  let (config_path, task, provider_str, model, cwd) = parse_cli_options(args)
  let config_file = match config_path {
    Some(p) => p
    None => {
      println("Error: config file path required")
      print_usage()
      return
    }
  }
  let task_str = match task {
    Some(t) => t
    None => {
      println("Error: --task is required")
      return
    }
  }
  // Read config file
  let json_str = @fs.read_file_to_string(config_file) catch {
    e => {
      println("Error reading config: \{e}")
      return
    }
  }
  // Parse config
  let config = @config.parse_piece_config(json_str) catch {
    e => {
      println("Error parsing config: \{e}")
      return
    }
  }
  // Determine provider
  let provider_type = match provider_str {
    Some("mock") => @types.ProviderType::Mock
    _ => @types.ProviderType::Claude
  }
  let project_cwd = cwd.unwrap_or(".")
  let provider = @provider.create_provider(provider_type, project_cwd, model)
  // Create callbacks with logging
  let callbacks = make_logging_callbacks()
  // Run
  println("=== tomate v\{version} ===")
  println("Piece: \{config.name}")
  println("Task: \{task_str}")
  println("Provider: \{provider_type}")
  println("")
  let state = @engine.run_piece(config, task_str, provider, callbacks)
  println("")
  println("=== Result ===")
  println("Status: \{state.status}")
  println("Iterations: \{state.iteration}")
}

///|
fn validate_config(args : Array[String]) -> Unit {
  let config_file = match args {
    [path, ..] => path
    _ => {
      println("Error: config file path required")
      return
    }
  }
  let json_str = @fs.read_file_to_string(config_file) catch {
    e => {
      println("Error reading config: \{e}")
      return
    }
  }
  let config = @config.parse_piece_config(json_str) catch {
    e => {
      println("Validation FAILED: \{e}")
      return
    }
  }
  println("Config is valid!")
  println("  Name: \{config.name}")
  println("  Movements: \{config.movements.length()}")
  println("  Initial: \{config.initial_movement}")
  println("  Max movements: \{config.max_movements}")
  // Verify initial movement exists
  let found = config.movements
    .iter()
    .any(fn(m) { m.name == config.initial_movement })
  if not(found) {
    println(
      "  WARNING: initial movement '\{config.initial_movement}' not found in movements",
    )
  }
  // Verify rule targets
  for m in config.movements {
    for r in m.rules {
      match r.next {
        Some(next) if next != "COMPLETE" && next != "ABORT" => {
          let target_found = config.movements
            .iter()
            .any(fn(mv) { mv.name == next })
          if not(target_found) {
            println(
              "  WARNING: rule in '\{m.name}' targets '\{next}' which doesn't exist",
            )
          }
        }
        _ => ()
      }
    }
  }
}

///|
fn debug_provider(args : Array[String]) -> Unit {
  println("=== Debug Provider ===")
  // Step 1: Test exec_command with echo
  println("\n[1] Testing exec_command with 'echo hello'...")
  let echo_result = @provider.exec_command("echo hello")
  println("  Result: '\{echo_result}'")
  println("  Length: \{echo_result.length()}")
  // Step 2: Test exec_command with claude --version
  println("\n[2] Testing exec_command with 'claude --version'...")
  let version_result = @provider.exec_command("claude --version")
  println("  Result: '\{version_result}'")
  println("  Length: \{version_result.length()}")
  // Step 3: Test claude -p with simple prompt
  if args.length() > 0 && args[0] == "--skip-claude" {
    println("\n[3] Skipping claude -p test (--skip-claude)")
    return
  }
  println("\n[3] Testing claude -p with simple prompt...")
  let cwd = "."
  let provider = @provider.ClaudeProvider::new(cwd, None)
  let resp = provider.call("", "Reply with exactly: HELLO_FROM_CLAUDE")
  println("  Status: \{resp.status}")
  println("  Content length: \{resp.content.length()}")
  if resp.content.length() > 0 {
    let preview = if resp.content.length() > 200 {
      resp.content.view(start_offset=0, end_offset=200).to_string() + "..."
    } else {
      resp.content
    }
    println("  Content: \{preview}")
  }
  match resp.error {
    Some(e) => println("  Error: \{e}")
    None => ()
  }
  // Step 4: Test with system prompt
  println("\n[4] Testing claude -p with system prompt...")
  let resp2 = provider.call(
    "You are a test assistant. Always include the tag <rule_0> in your response.",
    "Say hello briefly.",
  )
  println("  Status: \{resp2.status}")
  println("  Content length: \{resp2.content.length()}")
  if resp2.content.length() > 0 {
    let preview = if resp2.content.length() > 200 {
      resp2.content.view(start_offset=0, end_offset=200).to_string() + "..."
    } else {
      resp2.content
    }
    println("  Content: \{preview}")
    let has_tag = resp2.content.contains("<rule_0>")
    println("  Contains <rule_0>: \{has_tag}")
  }
  match resp2.error {
    Some(e) => println("  Error: \{e}")
    None => ()
  }
}

///|
fn make_logging_callbacks() -> @types.EngineCallbacks {
  {
    on_movement_start: fn(name, iter, _) {
      println("[\{iter}] Starting movement: \{name}")
    },
    on_movement_complete: fn(name, resp, _) {
      println("[\{name}] Complete (status: \{resp.status})")
      match resp.matched_rule_index {
        Some(idx) => println("  Matched rule: \{idx}")
        None => ()
      }
    },
    on_movement_report: fn(name, path, _) {
      println("[\{name}] Report: \{path}")
    },
    on_phase_start: fn(name, phase, _) {
      println("  [\{name}] Phase: \{phase}")
    },
    on_phase_complete: fn(_, _, _, _) {  },
    on_piece_complete: fn(_) { println("Piece completed successfully!") },
    on_piece_abort: fn(_, reason) { println("Piece aborted: \{reason}") },
    on_iteration_limit: fn(iter, max) {
      println("Iteration limit reached: \{iter}/\{max}")
    },
    on_loop_detected: fn(name, count) {
      println("Loop detected: \{name} x\{count}")
    },
    on_cycle_detected: fn(cycle, count) {
      println("Cycle detected: \{cycle} x\{count}")
    },
  }
}
