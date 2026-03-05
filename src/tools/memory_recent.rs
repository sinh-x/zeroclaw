use super::traits::{Tool, ToolResult};
use crate::memory::Memory;
use async_trait::async_trait;
use chrono::Utc;
use serde_json::json;
use std::fmt::Write;
use std::sync::Arc;

/// Let the agent retrieve recent memories by time range
pub struct MemoryRecentTool {
    memory: Arc<dyn Memory>,
}

impl MemoryRecentTool {
    pub fn new(memory: Arc<dyn Memory>) -> Self {
        Self { memory }
    }
}

#[async_trait]
impl Tool for MemoryRecentTool {
    fn name(&self) -> &str {
        "memory_recent"
    }

    fn description(&self) -> &str {
        "Retrieve recent memories by time range. Unlike memory_recall (semantic search), \
         this returns entries created within a specific time window, ordered newest first."
    }

    fn parameters_schema(&self) -> serde_json::Value {
        json!({
            "type": "object",
            "properties": {
                "since_hours": {
                    "type": "integer",
                    "description": "Look back this many hours from now (default: 24)"
                },
                "since": {
                    "type": "string",
                    "description": "RFC 3339 timestamp to look back from (overrides since_hours if provided)"
                },
                "category": {
                    "type": "string",
                    "description": "Filter by category (core, daily, conversation, or custom name)"
                },
                "limit": {
                    "type": "integer",
                    "description": "Max results to return (default: 50)"
                }
            }
        })
    }

    async fn execute(&self, args: serde_json::Value) -> anyhow::Result<ToolResult> {
        #[allow(clippy::cast_possible_truncation)]
        let limit = args
            .get("limit")
            .and_then(serde_json::Value::as_u64)
            .map_or(50, |v| v as usize);

        let since = if let Some(s) = args.get("since").and_then(|v| v.as_str()) {
            s.to_string()
        } else {
            let hours = args
                .get("since_hours")
                .and_then(serde_json::Value::as_u64)
                .unwrap_or(24);
            let cutoff = Utc::now() - chrono::Duration::hours(hours as i64);
            cutoff.to_rfc3339()
        };

        let category = args
            .get("category")
            .and_then(|v| v.as_str())
            .map(|s| match s {
                "core" => crate::memory::MemoryCategory::Core,
                "daily" => crate::memory::MemoryCategory::Daily,
                "conversation" => crate::memory::MemoryCategory::Conversation,
                other => crate::memory::MemoryCategory::Custom(other.to_string()),
            });

        match self
            .memory
            .recent(&since, limit, category.as_ref(), None)
            .await
        {
            Ok(entries) if entries.is_empty() => Ok(ToolResult {
                success: true,
                output: "No recent memories found in the specified time range.".into(),
                error: None,
            }),
            Ok(entries) => {
                let mut output = format!("Found {} recent memories:\n", entries.len());
                for entry in &entries {
                    let _ = writeln!(
                        output,
                        "- [{}] {}: {} ({})",
                        entry.category, entry.key, entry.content, entry.timestamp
                    );
                }
                Ok(ToolResult {
                    success: true,
                    output,
                    error: None,
                })
            }
            Err(e) => Ok(ToolResult {
                success: false,
                output: String::new(),
                error: Some(format!("Memory recent query failed: {e}")),
            }),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::memory::{MemoryCategory, SqliteMemory};
    use tempfile::TempDir;

    fn seeded_mem() -> (TempDir, Arc<dyn Memory>) {
        let tmp = TempDir::new().unwrap();
        let mem = SqliteMemory::new(tmp.path()).unwrap();
        (tmp, Arc::new(mem))
    }

    #[tokio::test]
    async fn recent_empty() {
        let (_tmp, mem) = seeded_mem();
        let tool = MemoryRecentTool::new(mem);
        let result = tool.execute(json!({"since_hours": 24})).await.unwrap();
        assert!(result.success);
        assert!(result.output.contains("No recent memories"));
    }

    #[tokio::test]
    async fn recent_finds_entries_within_window() {
        let (_tmp, mem) = seeded_mem();
        mem.store("lang", "User prefers Rust", MemoryCategory::Core, None)
            .await
            .unwrap();
        mem.store("tz", "Timezone is EST", MemoryCategory::Daily, None)
            .await
            .unwrap();

        let tool = MemoryRecentTool::new(mem);
        let result = tool.execute(json!({"since_hours": 1})).await.unwrap();
        assert!(result.success);
        assert!(result.output.contains("Found 2"));
        assert!(result.output.contains("Rust"));
        assert!(result.output.contains("EST"));
    }

    #[tokio::test]
    async fn recent_filters_by_category() {
        let (_tmp, mem) = seeded_mem();
        mem.store("lang", "User prefers Rust", MemoryCategory::Core, None)
            .await
            .unwrap();
        mem.store("log", "Session note", MemoryCategory::Daily, None)
            .await
            .unwrap();

        let tool = MemoryRecentTool::new(mem);
        let result = tool
            .execute(json!({"since_hours": 1, "category": "core"}))
            .await
            .unwrap();
        assert!(result.success);
        assert!(result.output.contains("Found 1"));
        assert!(result.output.contains("Rust"));
    }

    #[tokio::test]
    async fn recent_respects_limit() {
        let (_tmp, mem) = seeded_mem();
        for i in 0..10 {
            mem.store(
                &format!("k{i}"),
                &format!("Fact {i}"),
                MemoryCategory::Core,
                None,
            )
            .await
            .unwrap();
        }

        let tool = MemoryRecentTool::new(mem);
        let result = tool
            .execute(json!({"since_hours": 1, "limit": 3}))
            .await
            .unwrap();
        assert!(result.success);
        assert!(result.output.contains("Found 3"));
    }

    #[tokio::test]
    async fn recent_uses_rfc3339_since() {
        let (_tmp, mem) = seeded_mem();
        mem.store("recent", "Just now", MemoryCategory::Core, None)
            .await
            .unwrap();

        let tool = MemoryRecentTool::new(mem);
        // Use a far-future cutoff — should find nothing
        let result = tool
            .execute(json!({"since": "2099-01-01T00:00:00Z"}))
            .await
            .unwrap();
        assert!(result.success);
        assert!(result.output.contains("No recent memories"));
    }

    #[tokio::test]
    async fn recent_defaults_to_24_hours() {
        let (_tmp, mem) = seeded_mem();
        mem.store("fact", "Something", MemoryCategory::Core, None)
            .await
            .unwrap();

        let tool = MemoryRecentTool::new(mem);
        // No since_hours or since — should default to 24h
        let result = tool.execute(json!({})).await.unwrap();
        assert!(result.success);
        assert!(result.output.contains("Found 1"));
    }

    #[test]
    fn name_and_schema() {
        let (_tmp, mem) = seeded_mem();
        let tool = MemoryRecentTool::new(mem);
        assert_eq!(tool.name(), "memory_recent");
        let schema = tool.parameters_schema();
        assert!(schema["properties"]["since_hours"].is_object());
        assert!(schema["properties"]["since"].is_object());
        assert!(schema["properties"]["category"].is_object());
        assert!(schema["properties"]["limit"].is_object());
    }
}
