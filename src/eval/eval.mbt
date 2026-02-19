// Rule evaluation: tag detection and aggregate condition evaluation

///|
pub(all) struct RuleMatch {
  rule_index : Int
  match_method : @types.RuleMatchMethod
} derive(Eq, Show)

// Tag detection: check if content contains <tag_name> markers

///|
fn detect_tag(content : String, tag_name : String) -> Bool {
  let open_tag = "<\{tag_name}>"
  content.contains(open_tag)
}

///|
fn detect_rule_tag(content : String, rule_index : Int) -> Bool {
  detect_tag(content, "rule_\{rule_index}")
}

// Evaluate rules against agent response content

///|
pub fn evaluate_rules(
  rules : Array[@types.PieceRule],
  content : String,
) -> RuleMatch? {
  // Phase 1: Check tag detection for each rule
  for i, _rule in rules {
    if detect_rule_tag(content, i) {
      return Some({
        rule_index: i,
        match_method: @types.RuleMatchMethod::TagDetect,
      })
    }
  }
  // No tag match found - caller should fall back to AI judge
  None
}

// Aggregate evaluation: all() / any() conditions

///|
fn evaluate_aggregate_all(results : Array[Bool]) -> Bool {
  for result in results {
    if not(result) {
      return false
    }
  }
  true
}

///|
fn evaluate_aggregate_any(results : Array[Bool]) -> Bool {
  for result in results {
    if result {
      return true
    }
  }
  false
}

///|
pub fn evaluate_aggregate(
  aggregate_type : @types.AggregateType,
  results : Array[Bool],
) -> Bool {
  match aggregate_type {
    @types.AggregateType::All => evaluate_aggregate_all(results)
    @types.AggregateType::Any => evaluate_aggregate_any(results)
  }
}

// Full rule evaluation with aggregate support

///|
pub fn evaluate_rules_full(
  rules : Array[@types.PieceRule],
  content : String,
  sub_results : Array[Array[Bool]]?,
) -> RuleMatch? {
  // First try tag detection
  match evaluate_rules(rules, content) {
    Some(m) => return Some(m)
    None => ()
  }
  // Then check aggregate conditions
  for i, rule in rules {
    if rule.is_aggregate_condition {
      match (rule.aggregate_type, sub_results) {
        (Some(agg_type), Some(all_results)) =>
          if i < all_results.length() {
            if evaluate_aggregate(agg_type, all_results[i]) {
              return Some({
                rule_index: i,
                match_method: @types.RuleMatchMethod::Aggregate,
              })
            }
          }
        _ => ()
      }
    }
  }
  None
}
