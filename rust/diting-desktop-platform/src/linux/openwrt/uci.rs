use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;

pub async fn get_option(executor: &dyn CommandExecutor, key: &str) -> Option<String> {
    let output = executor.run("uci", &["-q", "get", key]).await.ok()?;
    if !output.success {
        return None;
    }
    let text = output.text();
    (!text.is_empty()).then_some(text)
}

pub async fn get_list(executor: &dyn CommandExecutor, key: &str) -> Vec<String> {
    let output = match executor.run("uci", &["-q", "-d", "\n", "get", key]).await {
        Ok(output) if output.success => output,
        _ => return Vec::new(),
    };
    parse_uci_list(&output.text())
}

pub fn parse_uci_list(raw: &str) -> Vec<String> {
    raw.lines()
        .flat_map(|line| line.split_whitespace())
        .map(str::trim)
        .filter(|item| !item.is_empty())
        .map(str::to_string)
        .collect()
}

pub async fn set_option(
    executor: &dyn CommandExecutor,
    key: &str,
    value: &str,
) -> PlatformResult<()> {
    let assignment = format!("{key}={value}");
    executor
        .run_checked("uci", &["set", &assignment])
        .await
        .map(|_| ())
}

pub async fn set_section(
    executor: &dyn CommandExecutor,
    package_and_name: &str,
    section_type: &str,
) -> PlatformResult<()> {
    set_option(executor, package_and_name, section_type).await
}

pub async fn delete_key(executor: &dyn CommandExecutor, key: &str) -> PlatformResult<()> {
    let _ = executor.run("uci", &["-q", "delete", key]).await?;
    Ok(())
}

pub async fn set_list(
    executor: &dyn CommandExecutor,
    key: &str,
    values: &[String],
) -> PlatformResult<()> {
    delete_key(executor, key).await?;
    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }
        let assignment = format!("{key}={trimmed}");
        executor
            .run_checked("uci", &["add_list", &assignment])
            .await?;
    }
    Ok(())
}

pub async fn commit(executor: &dyn CommandExecutor, package: &str) -> PlatformResult<()> {
    executor
        .run_checked("uci", &["commit", package])
        .await
        .map(|_| ())
}

pub async fn init_action(
    executor: &dyn CommandExecutor,
    service: &str,
    action: &str,
) -> PlatformResult<()> {
    let script = format!("/etc/init.d/{service}");
    executor
        .run_checked(&script, &[action])
        .await
        .map(|_| ())
        .map_err(|error| PlatformError::message(format!("执行 {script} {action} 失败: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_newline_and_space_delimited_lists() {
        assert_eq!(
            parse_uci_list("127.0.0.1#5354\n223.5.5.5"),
            vec!["127.0.0.1#5354".to_string(), "223.5.5.5".to_string()]
        );
        assert_eq!(
            parse_uci_list("1.1.1.1 8.8.8.8"),
            vec!["1.1.1.1".to_string(), "8.8.8.8".to_string()]
        );
        assert!(parse_uci_list("   \n  ").is_empty());
    }
}
