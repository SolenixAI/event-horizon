//! Link: how a Mac reaches the companion over the home network.

mod common;

use common::{FakeAwake, FakePrompt, FakeSunshine};
use event_horizon_companion::{Decision, Host, link};
use serde_json::{Value, json};
use std::path::Path;
use std::time::Duration;

async fn start(answer: Decision, tokens: &Path) -> (String, FakeAwake) {
    let awake = FakeAwake::default();
    let prompt = FakePrompt {
        answer: Some(answer),
        delay: Duration::ZERO,
    };
    let host = Host::new(FakeSunshine::default(), prompt, awake.clone());
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    tokio::spawn(link::serve(listener, host, tokens.to_path_buf()));
    (base, awake)
}

async fn pair(base: &str) -> (u16, Value) {
    let body = json!({ "mac_id": "mac-1", "mac_name": "Raptor", "pin": "4821", "code": "KX4TQZ" });
    let response = reqwest::Client::new()
        .post(format!("{base}/pair"))
        .json(&body)
        .send()
        .await
        .unwrap();
    (response.status().as_u16(), response.json().await.unwrap())
}

async fn lease(base: &str, token: Option<&str>) -> u16 {
    let mut request = reqwest::Client::new().post(format!("{base}/lease"));
    if let Some(token) = token {
        request = request.bearer_auth(token);
    }
    request.send().await.unwrap().status().as_u16()
}

#[tokio::test]
async fn allow_gives_the_mac_a_token_that_keeps_the_pc_awake() {
    let dir = tempfile::tempdir().unwrap();
    let (base, awake) = start(Decision::Allow, &dir.path().join("macs.json")).await;

    let (status, body) = pair(&base).await;
    assert_eq!(status, 200);
    assert_eq!(body["outcome"], "paired");
    let token = body["token"].as_str().expect("a token on Allow");
    assert!(token.len() >= 32);

    assert_eq!(lease(&base, Some(token)).await, 204);
    assert_eq!(awake.held(), 1);
}

#[tokio::test]
async fn a_lease_without_a_valid_token_is_refused() {
    let dir = tempfile::tempdir().unwrap();
    let (base, awake) = start(Decision::Allow, &dir.path().join("macs.json")).await;

    assert_eq!(lease(&base, None).await, 401);
    assert_eq!(lease(&base, Some("not-a-token")).await, 401);
    assert_eq!(awake.held(), 0);
}

#[tokio::test]
async fn deny_gives_no_token() {
    let dir = tempfile::tempdir().unwrap();
    let (base, _) = start(Decision::Deny, &dir.path().join("macs.json")).await;

    let (status, body) = pair(&base).await;
    assert_eq!(status, 403);
    assert_eq!(body["outcome"], "denied");
    assert!(body.get("token").is_none());
}

#[tokio::test]
async fn a_paired_mac_stays_paired_after_the_companion_restarts() {
    let dir = tempfile::tempdir().unwrap();
    let tokens = dir.path().join("macs.json");
    let (first, _) = start(Decision::Allow, &tokens).await;
    let (_, body) = pair(&first).await;
    let token = body["token"].as_str().unwrap().to_string();

    let (second, awake) = start(Decision::Allow, &tokens).await;

    assert_eq!(lease(&second, Some(&token)).await, 204);
    assert_eq!(awake.held(), 1);
}

#[tokio::test]
async fn hello_tells_a_mac_this_pc_runs_the_companion() {
    let dir = tempfile::tempdir().unwrap();
    let (base, _) = start(Decision::Allow, &dir.path().join("macs.json")).await;

    let body: Value = reqwest::get(format!("{base}/hello"))
        .await
        .unwrap()
        .json()
        .await
        .unwrap();

    assert_eq!(body["app"], "event-horizon-companion");
    assert_eq!(body["v"], 1);
}
