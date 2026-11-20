use std::borrow::Cow;

const DART_UNMAPPED: &[(u32, u32)] = &[
    (0x37F, 0x37F),
    (0x524, 0x524),
    (0x526, 0x526),
    (0x528, 0x528),
    (0x52A, 0x52A),
    (0x52C, 0x52C),
    (0x52E, 0x52E),
    (0x10C7, 0x10C7),
    (0x10CD, 0x10CD),
    (0x13A0, 0x13F5),
    (0x1C89, 0x1C89),
    (0x1C90, 0x1CBA),
    (0x1CBD, 0x1CBF),
    (0x2C2F, 0x2C2F),
    (0x2C70, 0x2C70),
    (0x2C7E, 0x2C7F),
    (0x2CEB, 0x2CEB),
    (0x2CED, 0x2CED),
    (0x2CF2, 0x2CF2),
    (0xA660, 0xA660),
    (0xA698, 0xA698),
    (0xA69A, 0xA69A),
    (0xA78D, 0xA78D),
    (0xA790, 0xA790),
    (0xA792, 0xA792),
    (0xA796, 0xA796),
    (0xA798, 0xA798),
    (0xA79A, 0xA79A),
    (0xA79C, 0xA79C),
    (0xA79E, 0xA79E),
    (0xA7A0, 0xA7A0),
    (0xA7A2, 0xA7A2),
    (0xA7A4, 0xA7A4),
    (0xA7A6, 0xA7A6),
    (0xA7A8, 0xA7A8),
    (0xA7AA, 0xA7AE),
    (0xA7B0, 0xA7B4),
    (0xA7B6, 0xA7B6),
    (0xA7B8, 0xA7B8),
    (0xA7BA, 0xA7BA),
    (0xA7BC, 0xA7BC),
    (0xA7BE, 0xA7BE),
    (0xA7C0, 0xA7C0),
    (0xA7C2, 0xA7C2),
    (0xA7C4, 0xA7C7),
    (0xA7C9, 0xA7C9),
    (0xA7CB, 0xA7CC),
    (0xA7CE, 0xA7CE),
    (0xA7D0, 0xA7D0),
    (0xA7D2, 0xA7D2),
    (0xA7D4, 0xA7D4),
    (0xA7D6, 0xA7D6),
    (0xA7D8, 0xA7D8),
    (0xA7DA, 0xA7DA),
    (0xA7DC, 0xA7DC),
    (0xA7F5, 0xA7F5),
    (0x104B0, 0x104D3),
    (0x10570, 0x1057A),
    (0x1057C, 0x1058A),
    (0x1058C, 0x10592),
    (0x10594, 0x10595),
    (0x10C80, 0x10CB2),
    (0x10D50, 0x10D65),
    (0x118A0, 0x118BF),
    (0x16E40, 0x16E5F),
    (0x16EA0, 0x16EB8),
    (0x1E900, 0x1E921),
];

pub fn fold(text: &str) -> Cow<'_, str> {
    if text.is_ascii() {
        if !text.bytes().any(|byte| byte.is_ascii_uppercase()) {
            return Cow::Borrowed(text);
        }
        return Cow::Owned(text.to_ascii_lowercase());
    }
    let mut folded = String::with_capacity(text.len());
    for character in text.chars() {
        if character == '\u{130}' {
            folded.push('i');
        } else if dart_leaves_unmapped(character) {
            folded.push(character);
        } else {
            folded.extend(character.to_lowercase());
        }
    }
    Cow::Owned(folded)
}

fn dart_leaves_unmapped(character: char) -> bool {
    let code = character as u32;
    DART_UNMAPPED
        .binary_search_by(|&(start, end)| {
            if code < start {
                std::cmp::Ordering::Greater
            } else if code > end {
                std::cmp::Ordering::Less
            } else {
                std::cmp::Ordering::Equal
            }
        })
        .is_ok()
}

#[derive(Debug)]
struct Row {
    pattern: Span,
    target: Option<Span>,
}

#[derive(Debug, Clone, Copy)]
struct Span {
    start: u32,
    len: u32,
}

#[derive(Debug, Default)]
pub struct RuleSearchIndex {
    text: String,
    rows: Vec<Row>,
}

impl RuleSearchIndex {
    pub fn with_capacity(rows: usize) -> Self {
        Self {
            text: String::new(),
            rows: Vec::with_capacity(rows),
        }
    }

    pub fn push(&mut self, pattern: &str, target: Option<&str>) {
        let pattern = self.store(pattern);
        let target = target.map(|text| self.store(text));
        self.rows.push(Row { pattern, target });
    }

    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn is_empty(&self) -> bool {
        self.rows.is_empty()
    }

    pub fn matching(&self, needle: &str) -> Vec<u32> {
        let needle = fold(needle);
        let needle: &str = &needle;
        let mut hits = Vec::new();
        for (index, row) in self.rows.iter().enumerate() {
            let hit = self.text_of(row.pattern).contains(needle)
                || row
                    .target
                    .is_some_and(|span| self.text_of(span).contains(needle));
            if hit {
                hits.push(index as u32);
            }
        }
        hits
    }

    fn store(&mut self, text: &str) -> Span {
        let start = self.text.len() as u32;
        self.text.push_str(&fold(text));
        Span {
            start,
            len: self.text.len() as u32 - start,
        }
    }

    fn text_of(&self, span: Span) -> &str {
        let start = span.start as usize;
        &self.text[start..start + span.len as usize]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hits(index: &RuleSearchIndex, needle: &str) -> Vec<u32> {
        index.matching(needle)
    }

    #[test]
    fn matches_patterns_and_targets_in_table_order() {
        let mut index = RuleSearchIndex::default();
        index.push("||ads.example.com^", None);
        index.push("||tracker.example.net^", Some("0.0.0.1"));
        index.push("||safe.example.org^", Some("1.1.1.1"));

        assert_eq!(hits(&index, "example"), vec![0, 1, 2]);
        assert_eq!(hits(&index, "EXAMPLE"), vec![0, 1, 2]);
        assert_eq!(hits(&index, "ads"), vec![0]);
        assert_eq!(hits(&index, "0.0.0.1"), vec![1]);
        assert_eq!(hits(&index, "nothing"), Vec::<u32>::new());
        assert_eq!(hits(&index, ""), vec![0, 1, 2]);
    }

    #[test]
    fn fold_matches_dart_for_the_awkward_cases() {
        assert_eq!(fold("ΑΣ"), "ασ");
        assert_eq!(fold("Σ"), "σ");
        assert_eq!(fold("İ"), "i");
        assert_eq!(fold("ẞ"), "ß");
        assert_eq!(fold("ǅ"), "ǆ");
        assert_eq!(fold("Ⅰ"), "ⅰ");
        assert_eq!(fold("\u{104B0}"), "\u{104B0}");
        assert_eq!(fold("\u{13A0}"), "\u{13A0}");
        assert_eq!(fold("ADs"), "ads");
        assert!(matches!(fold("already"), Cow::Borrowed(_)));
    }

    #[test]
    fn fold_handles_non_ascii_needles() {
        let mut index = RuleSearchIndex::default();
        index.push("||ÄPFEL.example.com^", None);
        index.push("||ähnlich.example.com^", None);
        assert_eq!(hits(&index, "ÄPFEL"), vec![0]);
        assert_eq!(hits(&index, "ähn"), vec![1]);
        assert_eq!(hits(&index, "ÄHN"), vec![1]);
    }

    #[test]
    fn unmapped_table_is_sorted_and_disjoint() {
        for pair in DART_UNMAPPED.windows(2) {
            assert!(
                pair[0].1 < pair[1].0,
                "{:x?} overlaps {:x?}",
                pair[0],
                pair[1]
            );
        }
    }

    #[test]
    fn empty_index_matches_nothing() {
        let index = RuleSearchIndex::default();
        assert!(index.is_empty());
        assert_eq!(hits(&index, "ads"), Vec::<u32>::new());
    }
}
