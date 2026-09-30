// sqlx::migrate!() マクロ用。migrations/ 内のファイル追加・変更を Cargo に通知し、
// proc macro を確実に再評価させる (古い compile 済みバイナリの使い回しで
// 同一 version に異なる checksum が混在するのを防ぐ)。
fn main() {
    println!("cargo:rerun-if-changed=migrations");
}
