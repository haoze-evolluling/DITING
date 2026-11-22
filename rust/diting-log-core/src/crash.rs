fn starts_block(line: &str) -> bool {
    line.starts_with("--------- beginning of") || line.starts_with("*** *** ***")
}

pub fn select(lines: &[String], package_name: &str) -> Vec<String> {
    let mut blocks: Vec<Vec<&str>> = Vec::new();
    for line in lines {
        if starts_block(line) || blocks.is_empty() {
            blocks.push(vec![line.as_str()]);
        } else {
            blocks
                .last_mut()
                .expect("a block exists")
                .push(line.as_str());
        }
    }
    blocks
        .into_iter()
        .filter(|block| block.iter().any(|line| line.contains(package_name)))
        .flatten()
        .map(|line| line.to_string())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(text: &[&str]) -> Vec<String> {
        text.iter().map(|line| line.to_string()).collect()
    }

    #[test]
    fn only_this_packages_blocks_survive() {
        let buffer = lines(&[
            "--------- beginning of crash",
            "FATAL EXCEPTION: main",
            "Process: com.haoze.diting, PID: 1",
            "java.lang.IllegalStateException",
            "--------- beginning of crash",
            "FATAL EXCEPTION: main",
            "Process: com.other.app, PID: 2",
            "--------- beginning of system",
            "*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***",
            "pid: 3, tid: 3, name: x  >>> com.haoze.diting <<<",
        ]);
        assert_eq!(
            select(&buffer, "com.haoze.diting"),
            lines(&[
                "--------- beginning of crash",
                "FATAL EXCEPTION: main",
                "Process: com.haoze.diting, PID: 1",
                "java.lang.IllegalStateException",
                "*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***",
                "pid: 3, tid: 3, name: x  >>> com.haoze.diting <<<",
            ])
        );
    }

    #[test]
    fn a_buffer_without_a_header_is_one_block() {
        let buffer = lines(&["first", "second com.haoze.diting"]);
        assert_eq!(select(&buffer, "com.haoze.diting"), buffer);
        assert!(select(&buffer, "com.other.app").is_empty());
        assert!(select(&[], "com.haoze.diting").is_empty());
    }

    #[test]
    fn a_blank_package_matches_every_block() {
        let buffer = lines(&["a", "b", "c"]);
        assert_eq!(select(&buffer, ""), buffer);
    }
}
