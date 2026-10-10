//! Pairing: a Mac asks, the person at the PC clicks Allow or Deny. The PC
//! shows a code of its own; the Mac shows the same code.

mod common;

use common::{FakeAwake, FakePrompt, FakeSunshine};
use event_horizon_companion::{Decision, Host, PairOutcome, PairRequest, new_code};

fn request(mac: &str, pin: &str) -> PairRequest {
    PairRequest {
        mac_id: mac.into(),
        mac_name: "Jager's MacBook Air".into(),
        pin: Some(pin.into()),
    }
}

fn paired(outcome: &PairOutcome) -> bool {
    matches!(outcome, PairOutcome::Paired { .. })
}

#[tokio::test(start_paused = true)]
async fn allow_pairs_the_mac_with_sunshine() {
    let sunshine = FakeSunshine::default();
    let host = Host::new(
        sunshine.clone(),
        FakePrompt::answers(Decision::Allow),
        FakeAwake::default(),
    );

    let outcome = host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await;

    assert!(paired(&outcome));
    assert_eq!(
        *sunshine.pins.lock().unwrap(),
        vec![("Jager's MacBook Air".to_string(), "4821".to_string())]
    );
}

#[tokio::test(start_paused = true)]
async fn the_pairing_keeps_the_sunshine_client_it_made() {
    let host = Host::new(
        FakeSunshine::default(),
        FakePrompt::answers(Decision::Allow),
        FakeAwake::default(),
    );

    let outcome = host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await;

    assert_eq!(
        outcome,
        PairOutcome::Paired {
            sunshine_client: Some("uuid-mac-1".into())
        }
    );
}

#[tokio::test(start_paused = true)]
async fn the_prompt_shows_the_code_the_mac_was_given() {
    let prompt = FakePrompt::answers(Decision::Allow);
    let host = Host::new(FakeSunshine::default(), prompt.clone(), FakeAwake::default());

    host.pair(request("mac-1", "4821"), "123456".into()).await;

    assert_eq!(*prompt.codes.lock().unwrap(), vec!["123456".to_string()]);
}

#[test]
fn a_code_is_six_digits() {
    for _ in 0..200 {
        let code = new_code();
        assert_eq!(code.len(), 6);
        assert!(code.bytes().all(|b| b.is_ascii_digit()));
    }
}

#[tokio::test(start_paused = true)]
async fn deny_refuses_and_sunshine_never_sees_the_pin() {
    let sunshine = FakeSunshine::default();
    let host = Host::new(
        sunshine.clone(),
        FakePrompt::answers(Decision::Deny),
        FakeAwake::default(),
    );

    let outcome = host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await;

    assert_eq!(outcome, PairOutcome::Denied);
    assert!(sunshine.pins.lock().unwrap().is_empty());
}

#[tokio::test(start_paused = true)]
async fn no_answer_in_two_minutes_expires() {
    let sunshine = FakeSunshine::default();
    let nobody = FakePrompt::after(None, std::time::Duration::ZERO);
    let host = Host::new(sunshine.clone(), nobody, FakeAwake::default());

    let started = tokio::time::Instant::now();
    let outcome = host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await;

    assert_eq!(outcome, PairOutcome::Expired);
    assert_eq!(started.elapsed(), std::time::Duration::from_secs(120));
    assert!(sunshine.pins.lock().unwrap().is_empty());
}

#[tokio::test(start_paused = true)]
async fn an_answer_just_inside_two_minutes_still_counts() {
    let sunshine = FakeSunshine::default();
    let slow = FakePrompt::after(Some(Decision::Allow), std::time::Duration::from_secs(119));
    let host = Host::new(sunshine.clone(), slow, FakeAwake::default());

    assert!(paired(
        &host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await
    ));
}

#[tokio::test(start_paused = true)]
async fn a_second_request_from_the_same_mac_replaces_the_first() {
    let sunshine = FakeSunshine::default();
    let clicks_after_30s =
        FakePrompt::after(Some(Decision::Allow), std::time::Duration::from_secs(30));
    let host = Host::new(sunshine.clone(), clicks_after_30s, FakeAwake::default());

    let first = host.pair(request("mac-1", "1111"), "111111".into());
    let second = async {
        tokio::time::sleep(std::time::Duration::from_secs(10)).await;
        host.pair(request("mac-1", "2222"), "222222".into()).await
    };
    let (first, second) = tokio::join!(first, second);

    assert_eq!(first, PairOutcome::Replaced);
    assert!(paired(&second));
    assert_eq!(
        *sunshine.pins.lock().unwrap(),
        vec![("Jager's MacBook Air".to_string(), "2222".to_string())]
    );
}

#[tokio::test(start_paused = true)]
async fn requests_from_two_macs_do_not_replace_each_other() {
    let sunshine = FakeSunshine::default();
    let host = Host::new(
        sunshine.clone(),
        FakePrompt::answers(Decision::Allow),
        FakeAwake::default(),
    );

    let (a, b) = tokio::join!(
        host.pair(request("mac-1", "1111"), "111111".into()),
        host.pair(request("mac-2", "2222"), "222222".into())
    );

    assert!(paired(&a) && paired(&b));
    assert_eq!(sunshine.pins.lock().unwrap().len(), 2);
}

#[tokio::test(start_paused = true)]
async fn allow_with_sunshine_down_says_so_instead_of_paired() {
    let sunshine = FakeSunshine::default();
    sunshine.go_down();
    let host = Host::new(
        sunshine,
        FakePrompt::answers(Decision::Allow),
        FakeAwake::default(),
    );

    assert_eq!(
        host.pair(request("mac-1", "4821"), "KX4TQZ".into()).await,
        PairOutcome::SunshineDown
    );
}

#[tokio::test(start_paused = true)]
async fn a_mac_already_paired_with_sunshine_only_needs_allow() {
    let sunshine = FakeSunshine::default();
    let host = Host::new(
        sunshine.clone(),
        FakePrompt::answers(Decision::Allow),
        FakeAwake::default(),
    );
    let link_only = PairRequest {
        pin: None,
        ..request("mac-1", "")
    };

    assert_eq!(
        host.pair(link_only, "KX4TQZ".into()).await,
        PairOutcome::Paired {
            sunshine_client: None
        }
    );
    assert!(
        sunshine.pins.lock().unwrap().is_empty(),
        "Sunshine is not touched"
    );
}
