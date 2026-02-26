import SwiftUI

/// View for configuring and managing the relay server connection.
struct ConnectionView: View {
    @ObservedObject var connection: RelayConnection
    @StateObject private var discovery = ServerDiscovery()
    @AppStorage("relay_host") private var host = ""
    @AppStorage("relay_port") private var port = 8765
    @State private var showManualEntry = false

    var body: some View {
        NavigationStack {
            List {
                // Connection status
                statusSection

                // Auto-discovered servers
                discoverySection

                // Manual connection
                manualSection

                // Info
                infoSection
            }
            .navigationTitle("接続設定")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                discovery.startDiscovery()
            }
            .onDisappear {
                discovery.stopDiscovery()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(connection.isConnected ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(connection.isConnected ? "接続中" : "未接続")
                            .fontWeight(.medium)
                    }

                    if let error = connection.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !host.isEmpty {
                        Text("\(host):\(port)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if connection.isConnected {
                    Button("切断") {
                        connection.disconnect()
                    }
                    .foregroundStyle(.red)
                }
            }
        } header: {
            Text("ステータス")
        }
    }

    // MARK: - Discovery

    private var discoverySection: some View {
        Section {
            if discovery.discoveredServers.isEmpty {
                HStack {
                    if discovery.isSearching {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("サーバーを検索中...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "wifi.exclamationmark")
                            .foregroundStyle(.secondary)
                        Text("サーバーが見つかりません")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ForEach(discovery.discoveredServers) { server in
                    Button {
                        host = server.host
                        port = server.port
                        connection.connect(host: server.host, port: server.port)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(server.name)
                                    .fontWeight(.medium)
                                Text("\(server.host):\(server.port)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.purple)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Button {
                discovery.startDiscovery()
            } label: {
                Label("再検索", systemImage: "arrow.clockwise")
            }
        } header: {
            Text("ネットワーク上のサーバー")
        } footer: {
            Text("同じWiFiに接続されたPCのリレーサーバーが自動検出されます")
        }
    }

    // MARK: - Manual

    private var manualSection: some View {
        Section {
            HStack {
                TextField("ホスト (例: 192.168.1.10)", text: $host)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }

            HStack {
                Text("ポート")
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("8765", value: $port, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            Button {
                guard !host.isEmpty else { return }
                connection.connect(host: host, port: port)
            } label: {
                HStack {
                    Spacer()
                    Text("接続")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(host.isEmpty)
        } header: {
            Text("手動接続")
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("セットアップ", systemImage: "questionmark.circle")
                    .fontWeight(.medium)

                Text("""
                PCで以下のコマンドを実行してください:

                cd ios-remote/server
                pip install -r requirements.txt
                python3 relay_server.py
                """)
                .font(.system(size: 12, design: .monospaced))
                .padding(10)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("ヘルプ")
        }
    }
}

#Preview {
    ConnectionView(connection: RelayConnection())
}
