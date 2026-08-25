#[tokio::test]
async fn bridge_pool_acquires_new_and_reused_sockets() {
    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind listener");
    let addr = listener.local_addr().expect("listener local addr");
    let accept_task = tokio::spawn(async move {
        let (_stream, _) = listener.accept().await.expect("accept socket");
        tokio::time::sleep(Duration::from_millis(50)).await;
    });

    let pool = BridgePool::new(BridgeEndpoint::Tcp(addr.to_string()), 1);
    let stream = pool.acquire().await.expect("acquire fresh socket");
    pool.release(stream);

    let stream = pool.acquire().await.expect("acquire reused socket");
    drop(stream);

    accept_task.await.expect("accept task should complete");
}
use super::*;
use tokio::net::TcpListener;
