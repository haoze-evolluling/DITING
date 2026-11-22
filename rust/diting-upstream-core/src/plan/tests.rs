use super::*;

#[test]
fn the_mode_table_keeps_its_aliases_and_default() {
    assert_eq!(strategy("single"), Strategy::Single);
    assert_eq!(strategy("primary_backup"), Strategy::PrimaryBackup);
    assert_eq!(strategy("parallel_race"), Strategy::ParallelRace);
    assert_eq!(strategy("race"), Strategy::ParallelRace);
    assert_eq!(strategy("smart_prediction"), Strategy::SmartPrediction);
    assert_eq!(strategy("prediction"), Strategy::SmartPrediction);
    for unknown in ["", "Single", "parallel", " primary_backup", "nope"] {
        assert_eq!(strategy(unknown), Strategy::Single, "mode {unknown:?}");
    }
}

#[test]
fn only_refused_formerr_and_notimp_are_policy_rejections() {
    for rcode in [1, 4, 5] {
        assert!(is_policy_rejection(rcode), "rcode {rcode}");
    }
    for rcode in [0, 2, 3, 6, 16, -1] {
        assert!(!is_policy_rejection(rcode), "rcode {rcode}");
    }
}
