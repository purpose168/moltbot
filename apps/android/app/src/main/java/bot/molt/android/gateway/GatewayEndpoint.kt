package bot.molt.android.gateway

/**
 * 网关端点数据类
 * 表示一个网关服务端点
 * @param stableId 稳定ID(用于唯一标识)
 * @param name 显示名称
 * @param host 主机地址
 * @param port 端口号
 * @param lanHost 局域主机地址
 * @param tailnetDns Tailscale DNS
 * @param gatewayPort 网关端口
 * @param canvasPort Canvas端口
 * @param tlsEnabled 是否启用TLS
 * @param tlsFingerprintSha256 TLS指纹(SHA256)
 */
data class GatewayEndpoint(
  val stableId: String,
  val name: String,
  val host: String,
  val port: Int,
  val lanHost: String? = null,
  val tailnetDns: String? = null,
  val gatewayPort: Int? = null,
  val canvasPort: Int? = null,
  val tlsEnabled: Boolean = false,
  val tlsFingerprintSha256: String? = null,
) {
  companion object {
    /**
     * 创建手动配置的网关端点
     * @param host 主机地址
     * @param port 端口号
     * @return 手动网关端点
     */
    fun manual(host: String, port: Int): GatewayEndpoint =
      GatewayEndpoint(
        stableId = "manual|${host.lowercase()}|$port",
        name = "$host:$port",
        host = host,
        port = port,
        tlsEnabled = false,
        tlsFingerprintSha256 = null,
      )
  }
}
