//! RFC 1035 zone-file subset parser.
//!
//! The Go engine delegated this to `miekg/dns`'s `ZoneParser`; this is the subset the desktop
//! service needs, with the same directives and record grammar:
//!
//! * `$ORIGIN`, `$TTL`, `$GENERATE`; `$INCLUDE` is rejected outright because it reads host files.
//! * relative / absolute names, `@`, `( … )` continuations, `;` comments, quoted TXT strings.
//! * A / AAAA / CNAME / PTR / NS / MX / TXT / SRV / SOA / CAA, class `IN` or omitted, TTL column
//!   optional and accepted before or after the class.
//!
//! `$GENERATE` expands into normal record statements, so the record budget applies while it
//! expands instead of only afterwards.

use super::records::{
    is_class, is_ttl_token, normalize_origin, parse_ttl, parse_u16, parse_u32, parse_u8,
    record_type, resolve_name, ZoneRData, ZoneRecord, TYPE_A, TYPE_AAAA, TYPE_CAA, TYPE_CNAME,
    TYPE_MX, TYPE_NS, TYPE_PTR, TYPE_SOA, TYPE_SRV, TYPE_TXT,
};

/// Hard cap on generated iterations so a non-IN `$GENERATE` cannot spin for billions of rounds
/// without ever consuming the record budget.
const MAX_GENERATE_ITERATIONS: u64 = 1_000_000;

#[derive(Debug)]
struct Statement {
    tokens: Vec<String>,
    /// True when the logical line started with whitespace (owner is inherited).
    blank_owner: bool,
}

/// The parse result for one zone entry.
#[derive(Debug)]
pub(crate) struct ParsedZone {
    /// Normalized apex from the entry (not the last `$ORIGIN`).
    pub origin: String,
    pub records: Vec<ZoneRecord>,
    /// Explicit apex SOA, if the zone declared one.
    pub soa: Option<ZoneRecord>,
    pub count: usize,
    pub truncated: bool,
}

/// Parses one zone entry. `budget` is the remaining global record allowance.
pub(crate) fn parse_zone(
    raw_origin: &str,
    content: &str,
    default_ttl: u32,
    budget: usize,
) -> Result<ParsedZone, String> {
    let origin = normalize_origin(raw_origin)?;
    let mut parser = Parser {
        zone_origin: origin.clone(),
        origin: origin.clone(),
        default_ttl: if default_ttl == 0 { 300 } else { default_ttl },
        prev_owner: None,
        budget,
        parsed: ParsedZone {
            origin,
            records: Vec::new(),
            soa: None,
            count: 0,
            truncated: false,
        },
    };
    if content.trim().is_empty() {
        return Ok(parser.parsed);
    }
    for statement in lex(content)? {
        if parser.parsed.truncated {
            break;
        }
        parser.process_statement(&statement)?;
    }
    Ok(parser.parsed)
}

struct Parser {
    /// The entry's apex, used to decide which SOA is the zone SOA.
    zone_origin: String,
    /// Current `$ORIGIN`.
    origin: String,
    default_ttl: u32,
    prev_owner: Option<String>,
    budget: usize,
    parsed: ParsedZone,
}

impl Parser {
    fn process_statement(&mut self, statement: &Statement) -> Result<(), String> {
        let Some(first) = statement.tokens.first() else {
            return Ok(());
        };
        if !first.starts_with('$') {
            return self.process_record(&statement.tokens, statement.blank_owner);
        }
        match first.to_ascii_uppercase().as_str() {
            "$ORIGIN" => {
                expect_fields(&statement.tokens, 2, "$ORIGIN")?;
                self.origin = resolve_name(&statement.tokens[1], &self.origin)?;
                Ok(())
            }
            "$TTL" => {
                expect_fields(&statement.tokens, 2, "$TTL")?;
                self.default_ttl = parse_ttl(&statement.tokens[1])
                    .ok_or_else(|| format!("$TTL 取值 {:?} 无法解析", statement.tokens[1]))?;
                Ok(())
            }
            "$INCLUDE" => Err("$INCLUDE 不被支持".to_string()),
            "$GENERATE" => self.process_generate(&statement.tokens[1..]),
            _ => Err(format!("不支持的区指令 {first}")),
        }
    }

    fn process_generate(&mut self, args: &[String]) -> Result<(), String> {
        if args.len() < 2 {
            return Err("$GENERATE 需要「区间 模板」两个字段".to_string());
        }
        let (start, stop, step) = parse_range(&args[0])?;
        let template = &args[1..];
        let mut value = u64::from(start);
        let mut iterations = 0u64;
        while value <= u64::from(stop) {
            if iterations >= MAX_GENERATE_ITERATIONS {
                return Err("$GENERATE 展开数超出上限".to_string());
            }
            iterations += 1;
            let tokens: Vec<String> = template
                .iter()
                .map(|token| substitute(token, value))
                .collect();
            self.process_record(&tokens, false)?;
            if self.parsed.truncated {
                return Ok(());
            }
            value += u64::from(step);
        }
        Ok(())
    }

    fn process_record(&mut self, tokens: &[String], blank_owner: bool) -> Result<(), String> {
        if tokens.is_empty() {
            return Ok(());
        }
        let (owner, mut index) = if blank_owner {
            let owner = self
                .prev_owner
                .clone()
                .ok_or_else(|| "记录缺少属主名".to_string())?;
            (owner, 0)
        } else {
            (resolve_name(&tokens[0], &self.origin)?, 1)
        };

        let mut ttl = None;
        let mut class = None;
        while let Some(token) = tokens.get(index) {
            if ttl.is_none() && is_ttl_token(token) {
                ttl = Some(parse_ttl(token).ok_or_else(|| format!("TTL {token:?} 无法解析"))?);
                index += 1;
                continue;
            }
            if class.is_none() && is_class(token) {
                class = Some(token.to_ascii_uppercase());
                index += 1;
                continue;
            }
            break;
        }
        let Some(type_token) = tokens.get(index) else {
            return Err("记录缺少记录类型".to_string());
        };
        let rtype =
            record_type(type_token).ok_or_else(|| format!("不支持的记录类型 {type_token:?}"))?;
        index += 1;

        // The Go loop stopped before adding the record once the budget was exhausted.
        if self.parsed.count >= self.budget {
            self.parsed.truncated = true;
            return Ok(());
        }
        // The owner is inherited even for records the IN-only index later discards.
        self.prev_owner = Some(owner.clone());
        if class.as_deref().is_some_and(|class| class != "IN") {
            return Ok(());
        }

        let ttl = ttl.unwrap_or(self.default_ttl);
        let rdata = build_rdata(rtype, &tokens[index..], &self.origin)?;
        if rtype == TYPE_SOA && owner == self.zone_origin {
            self.parsed.soa = Some(ZoneRecord {
                owner: owner.clone(),
                rtype,
                ttl,
                rdata: rdata.clone(),
            });
        }
        self.parsed.records.push(ZoneRecord {
            owner,
            rtype,
            ttl,
            rdata,
        });
        self.parsed.count += 1;
        Ok(())
    }
}

fn build_rdata(rtype: u16, tokens: &[String], origin: &str) -> Result<ZoneRData, String> {
    match rtype {
        TYPE_A => {
            expect_fields(tokens, 1, "A")?;
            let address = tokens[0]
                .parse()
                .map_err(|_| format!("A 记录的地址 {:?} 无效", tokens[0]))?;
            Ok(ZoneRData::A(address))
        }
        TYPE_AAAA => {
            expect_fields(tokens, 1, "AAAA")?;
            let address = tokens[0]
                .parse()
                .map_err(|_| format!("AAAA 记录的地址 {:?} 无效", tokens[0]))?;
            Ok(ZoneRData::Aaaa(address))
        }
        TYPE_CNAME => {
            expect_fields(tokens, 1, "CNAME")?;
            Ok(ZoneRData::Cname(resolve_name(&tokens[0], origin)?))
        }
        TYPE_PTR => {
            expect_fields(tokens, 1, "PTR")?;
            Ok(ZoneRData::Ptr(resolve_name(&tokens[0], origin)?))
        }
        TYPE_NS => {
            expect_fields(tokens, 1, "NS")?;
            Ok(ZoneRData::Ns(resolve_name(&tokens[0], origin)?))
        }
        TYPE_MX => {
            expect_fields(tokens, 2, "MX")?;
            Ok(ZoneRData::Mx {
                preference: parse_u16(&tokens[0])?,
                exchange: resolve_name(&tokens[1], origin)?,
            })
        }
        TYPE_SRV => {
            expect_fields(tokens, 4, "SRV")?;
            Ok(ZoneRData::Srv {
                priority: parse_u16(&tokens[0])?,
                weight: parse_u16(&tokens[1])?,
                port: parse_u16(&tokens[2])?,
                target: resolve_name(&tokens[3], origin)?,
            })
        }
        TYPE_SOA => {
            expect_fields(tokens, 7, "SOA")?;
            Ok(ZoneRData::Soa {
                mname: resolve_name(&tokens[0], origin)?,
                rname: resolve_name(&tokens[1], origin)?,
                serial: parse_u32(&tokens[2])?,
                refresh: parse_ttl(&tokens[3])
                    .ok_or_else(|| format!("SOA refresh {:?} 无法解析", tokens[3]))?,
                retry: parse_ttl(&tokens[4])
                    .ok_or_else(|| format!("SOA retry {:?} 无法解析", tokens[4]))?,
                expire: parse_ttl(&tokens[5])
                    .ok_or_else(|| format!("SOA expire {:?} 无法解析", tokens[5]))?,
                minimum: parse_ttl(&tokens[6])
                    .ok_or_else(|| format!("SOA minimum {:?} 无法解析", tokens[6]))?,
            })
        }
        TYPE_CAA => {
            expect_fields(tokens, 3, "CAA")?;
            Ok(ZoneRData::Caa {
                flags: parse_u8(&tokens[0])?,
                tag: tokens[1].to_ascii_lowercase(),
                value: tokens[2].clone(),
            })
        }
        TYPE_TXT => {
            if tokens.is_empty() {
                return Err("TXT 记录缺少取值".to_string());
            }
            Ok(ZoneRData::Txt(tokens.to_vec()))
        }
        other => Err(format!("记录类型 {other} 暂未支持")),
    }
}

fn expect_fields(tokens: &[String], expected: usize, name: &str) -> Result<(), String> {
    if tokens.len() != expected {
        return Err(format!(
            "{name} 记录需要 {expected} 个字段，得到 {}",
            tokens.len()
        ));
    }
    Ok(())
}

fn parse_range(range: &str) -> Result<(u32, u32, u32), String> {
    let (start, rest) = range
        .split_once('-')
        .ok_or_else(|| format!("$GENERATE 区间 {range:?} 无效"))?;
    let (stop, step) = match rest.split_once('/') {
        Some((stop, step)) => (
            stop.parse::<u32>()
                .map_err(|_| format!("$GENERATE 区间 {range:?} 无效"))?,
            step.parse::<u32>()
                .map_err(|_| format!("$GENERATE 步长 {step:?} 无效"))?,
        ),
        None => (
            rest.parse::<u32>()
                .map_err(|_| format!("$GENERATE 区间 {range:?} 无效"))?,
            1,
        ),
    };
    let start = start
        .parse::<u32>()
        .map_err(|_| format!("$GENERATE 区间 {range:?} 无效"))?;
    if step == 0 || start > stop {
        return Err(format!("$GENERATE 区间 {range:?} 无效"));
    }
    Ok((start, stop, step))
}

/// `$` and `${offset,width,base}` substitution used by `$GENERATE`.
fn substitute(token: &str, value: u64) -> String {
    let mut output = String::new();
    let mut chars = token.chars().peekable();
    while let Some(character) = chars.next() {
        if character != '$' {
            output.push(character);
            continue;
        }
        if chars.peek() != Some(&'{') {
            output.push_str(&value.to_string());
            continue;
        }
        chars.next();
        let mut spec = String::new();
        while let Some(&next) = chars.peek() {
            chars.next();
            if next == '}' {
                break;
            }
            spec.push(next);
        }
        output.push_str(&expand_spec(&spec, value));
    }
    output
}

fn expand_spec(spec: &str, value: u64) -> String {
    let mut fields = spec.split(',');
    let offset = fields
        .next()
        .and_then(|field| field.parse::<i64>().ok())
        .unwrap_or(0);
    let width = fields
        .next()
        .and_then(|field| field.parse::<usize>().ok())
        .unwrap_or(0);
    let base = fields.next().unwrap_or("d");
    let number = (value as i64).wrapping_add(offset);
    let (sign, magnitude) = if number < 0 {
        ("-", number.unsigned_abs())
    } else {
        ("", number as u64)
    };
    let digits = match base {
        "o" => format!("{magnitude:o}"),
        "x" => format!("{magnitude:x}"),
        "X" => format!("{magnitude:X}"),
        _ => format!("{magnitude}"),
    };
    format!("{sign}{digits:0>width$}")
}

/// Splits the text into logical statements (parentheses join lines) and tokens.
fn lex(content: &str) -> Result<Vec<Statement>, String> {
    let mut statements = Vec::new();
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut has_token = false;
    let mut in_quote = false;
    let mut depth = 0usize;
    let mut blank_owner = false;
    let mut at_start = true;
    let mut chars = content.chars().peekable();

    while let Some(character) = chars.next() {
        if in_quote {
            match character {
                '"' => in_quote = false,
                '\\' => {
                    let Some(next) = chars.next() else {
                        return Err("字符串缺少结束引号".to_string());
                    };
                    if next.is_ascii_digit() {
                        let mut code = next.to_digit(10).unwrap();
                        for _ in 0..2 {
                            match chars.peek() {
                                Some(peek) if peek.is_ascii_digit() => {
                                    code = code * 10 + chars.next().unwrap().to_digit(10).unwrap();
                                }
                                _ => break,
                            }
                        }
                        if let Some(character) = char::from_u32(code) {
                            current.push(character);
                        }
                    } else {
                        current.push(next);
                    }
                }
                _ => current.push(character),
            }
            continue;
        }

        match character {
            '"' => {
                in_quote = true;
                has_token = true;
                at_start = false;
            }
            '(' => {
                flush_token(&mut tokens, &mut current, &mut has_token);
                depth += 1;
                at_start = false;
            }
            ')' => {
                flush_token(&mut tokens, &mut current, &mut has_token);
                depth = depth.saturating_sub(1);
                at_start = false;
            }
            ';' => {
                flush_token(&mut tokens, &mut current, &mut has_token);
                while let Some(&next) = chars.peek() {
                    if next == '\n' {
                        break;
                    }
                    chars.next();
                }
            }
            '\r' => {}
            '\n' => {
                flush_token(&mut tokens, &mut current, &mut has_token);
                if depth == 0 {
                    if !tokens.is_empty() {
                        statements.push(Statement {
                            tokens: std::mem::take(&mut tokens),
                            blank_owner,
                        });
                    }
                    blank_owner = false;
                    at_start = true;
                }
            }
            ' ' | '\t' => {
                flush_token(&mut tokens, &mut current, &mut has_token);
                if at_start {
                    blank_owner = true;
                    at_start = false;
                }
            }
            _ => {
                current.push(character);
                has_token = true;
                at_start = false;
            }
        }
    }

    if in_quote {
        return Err("字符串缺少结束引号".to_string());
    }
    if depth != 0 {
        return Err("括号未闭合".to_string());
    }
    flush_token(&mut tokens, &mut current, &mut has_token);
    if !tokens.is_empty() {
        statements.push(Statement {
            tokens,
            blank_owner,
        });
    }
    Ok(statements)
}

fn flush_token(tokens: &mut Vec<String>, current: &mut String, has_token: &mut bool) {
    if *has_token {
        tokens.push(std::mem::take(current));
        *has_token = false;
    } else {
        current.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_directives_owner_inheritance_and_ttl() {
        let parsed = parse_zone(
            "lan",
            "$ORIGIN lan.\n$TTL 600\n@ IN SOA ns.lan. admin.lan. (1 7200 3600 1209600 300)\nwww IN A 10.0.0.1\n    AAAA 2001:db8::1\n",
            300,
            10_000,
        )
        .unwrap();
        assert_eq!(parsed.count, 3);
        assert!(parsed.soa.is_some());
        let www = parsed
            .records
            .iter()
            .find(|record| record.owner == "www.lan.")
            .unwrap();
        assert_eq!(www.ttl, 600);
        let v6 = parsed
            .records
            .iter()
            .find(|record| record.rtype == TYPE_AAAA)
            .unwrap();
        assert_eq!(v6.owner, "www.lan.");
        assert_eq!(v6.ttl, 600);
    }

    #[test]
    fn quoted_txt_and_comments() {
        let parsed = parse_zone(
            "lan",
            "text IN TXT \"hello world\" \"second\" ; trailing\n; whole line\n",
            60,
            100,
        )
        .unwrap();
        assert_eq!(
            parsed.records[0].rdata,
            ZoneRData::Txt(vec!["hello world".to_string(), "second".to_string()])
        );
    }

    #[test]
    fn rejects_include_and_unknown_types() {
        assert!(parse_zone("lan", "$INCLUDE /etc/passwd\n", 60, 100)
            .unwrap_err()
            .contains("INCLUDE"));
        assert!(parse_zone("lan", "not a zone file at all !!!\n", 60, 100).is_err());
        assert!(parse_zone("", "www A 10.0.0.1\n", 60, 100).is_err());
    }

    #[test]
    fn generate_respects_budget() {
        let parsed = parse_zone("lan", "$GENERATE 1-50000 host$ IN A 10.0.0.1\n", 60, 100).unwrap();
        assert!(parsed.truncated);
        assert_eq!(parsed.count, 100);
        assert_eq!(parsed.records[99].owner, "host100.lan.");
    }

    #[test]
    fn generate_supports_offsets_and_hex() {
        let parsed = parse_zone("lan", "$GENERATE 1-2 host${0,2,x} A 10.0.0.1\n", 60, 100).unwrap();
        assert_eq!(parsed.records[0].owner, "host01.lan.");
        assert_eq!(parsed.records[1].owner, "host02.lan.");
    }

    #[test]
    fn parses_all_supported_rdata() {
        let parsed = parse_zone(
            "example.com",
            "ns1 A 10.0.0.1\nalias CNAME www\nmail MX 32 mailhost\n_sip._tcp SRV 10 60 8080 sip\n@ CAA 0 issue \"letsencrypt.org\"\nptr PTR host\nns NS ns1\n",
            60,
            100,
        )
        .unwrap();
        assert_eq!(parsed.count, 7);
    }

    #[test]
    fn non_in_class_is_dropped_and_owner_still_inherited() {
        let parsed = parse_zone("lan", "a 60 CH A 10.0.0.1\n    A 10.0.0.2\n", 60, 100).unwrap();
        assert_eq!(parsed.count, 1);
        assert_eq!(parsed.records[0].owner, "a.lan.");
        assert_eq!(parsed.records[0].ttl, 60);
    }
}
