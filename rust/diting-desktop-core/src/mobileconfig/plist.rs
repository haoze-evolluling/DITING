pub(crate) struct PlistEntry {
    pub key: String,
    pub value: String,
}

pub(crate) fn plist_dict(entries: &[PlistEntry]) -> String {
    let mut output = String::from("<dict>\n");
    for entry in entries {
        output.push_str("<key>");
        output.push_str(&escape_xml_text(&entry.key));
        output.push_str("</key>\n");
        output.push_str(&entry.value);
        if !entry.value.ends_with('\n') {
            output.push('\n');
        }
    }
    output.push_str("</dict>");
    output
}

pub(crate) fn plist_array(values: &[String]) -> String {
    let mut output = String::from("<array>\n");
    for value in values {
        output.push_str(value);
        if !value.ends_with('\n') {
            output.push('\n');
        }
    }
    output.push_str("</array>");
    output
}

pub(crate) fn plist_string(value: &str) -> String {
    format!("<string>{}</string>", escape_xml_text(value))
}

pub(crate) fn plist_integer(value: i64) -> String {
    format!("<integer>{value}</integer>")
}

pub(crate) fn escape_xml_text(value: &str) -> String {
    let mut output = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '&' => output.push_str("&amp;"),
            '<' => output.push_str("&lt;"),
            '>' => output.push_str("&gt;"),
            '"' => output.push_str("&quot;"),
            '\'' => output.push_str("&apos;"),
            character if character < '\u{20}' => {
                if matches!(character, '\t' | '\n' | '\r') {
                    output.push(character);
                }
            }
            character => output.push(character),
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn escaping_covers_reserved_characters() {
        assert_eq!(escape_xml_text("&<>\"'"), "&amp;&lt;&gt;&quot;&apos;");
        assert_eq!(escape_xml_text("A & B"), "A &amp; B");
    }

    #[test]
    fn control_characters_are_dropped_but_whitespace_survives() {
        assert_eq!(escape_xml_text("a\u{1}b\u{1f}c"), "abc");
        assert_eq!(escape_xml_text("a\tb\nc\rd"), "a\tb\nc\rd");
    }

    #[test]
    fn serializers_emit_the_expected_shape() {
        assert_eq!(plist_string(""), "<string></string>");
        assert_eq!(plist_integer(1), "<integer>1</integer>");

        let dict = plist_dict(&[
            PlistEntry {
                key: "Key&".to_string(),
                value: plist_string("value"),
            },
            PlistEntry {
                key: "Second".to_string(),
                value: plist_integer(2),
            },
        ]);
        assert_eq!(
            dict,
            "<dict>\n<key>Key&amp;</key>\n<string>value</string>\n<key>Second</key>\n<integer>2</integer>\n</dict>"
        );

        let array = plist_array(&[plist_string("a"), plist_integer(3)]);
        assert_eq!(
            array,
            "<array>\n<string>a</string>\n<integer>3</integer>\n</array>"
        );
    }

    #[test]
    fn preformatted_values_do_not_gain_a_second_newline() {
        let dict = plist_dict(&[PlistEntry {
            key: "Nested".to_string(),
            value: plist_dict(&[]),
        }]);
        assert_eq!(dict, "<dict>\n<key>Nested</key>\n<dict>\n</dict>\n</dict>");
    }
}
