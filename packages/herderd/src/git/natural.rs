//! Ordering for names a person reads: case-insensitive, with runs of digits
//! compared as numbers, so `feature-2` sorts before `feature-10`. It stands in
//! for the app's old `localizedStandardCompare`.

use std::cmp::Ordering;

pub fn compare(lhs: &str, rhs: &str) -> Ordering {
    let mut a = lhs.chars().peekable();
    let mut b = rhs.chars().peekable();
    loop {
        match (a.peek().copied(), b.peek().copied()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) if x.is_ascii_digit() && y.is_ascii_digit() => {
                let x = take_number(&mut a);
                let y = take_number(&mut b);
                let (x, y) = (x.trim_start_matches('0'), y.trim_start_matches('0'));
                let order = x.len().cmp(&y.len()).then_with(|| x.cmp(y));
                if order != Ordering::Equal {
                    return order;
                }
            }
            (Some(x), Some(y)) => {
                let order = x.to_lowercase().cmp(y.to_lowercase());
                if order != Ordering::Equal {
                    return order;
                }
                a.next();
                b.next();
            }
        }
    }
}

fn take_number(chars: &mut std::iter::Peekable<std::str::Chars>) -> String {
    let mut digits = String::new();
    while let Some(c) = chars.next_if(char::is_ascii_digit) {
        digits.push(c);
    }
    digits
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn digits_compare_as_numbers_and_case_is_ignored() {
        let mut names = vec!["feature-10", "Feature-2", "alpha", "feature-1"];
        names.sort_by(|a, b| compare(a, b));
        assert_eq!(names, ["alpha", "feature-1", "Feature-2", "feature-10"]);
    }
}
