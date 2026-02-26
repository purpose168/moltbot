import MoltbotKit
import Network
import Testing
@testable import Moltbot

@Suite struct GatewayEndpointIDTests {
    /// 测试服务端点的稳定ID是否能正确解码并标准化名称
    @Test func stableIDForServiceDecodesAndNormalizesName() {
        let endpoint = NWEndpoint.service(
            name: "Moltbot\\032Gateway   \\032  Node\n",
            type: "_moltbot-gw._tcp",
            domain: "local.",
            interface: nil)

        #expect(GatewayEndpointID.stableID(endpoint) == "_moltbot-gw._tcp|local.|Moltbot Gateway Node")
    }

    /// 测试非服务端点是否使用端点描述作为稳定ID
    @Test func stableIDForNonServiceUsesEndpointDescription() {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: 4242)
        #expect(GatewayEndpointID.stableID(endpoint) == String(describing: endpoint))
    }

    /// 测试美化描述是否能正确解码Bonjour转义序列
    @Test func prettyDescriptionDecodesBonjourEscapes() {
        let endpoint = NWEndpoint.service(
            name: "Moltbot\\032Gateway",
            type: "_moltbot-gw._tcp",
            domain: "local.",
            interface: nil)

        let pretty = GatewayEndpointID.prettyDescription(endpoint)
        #expect(pretty == BonjourEscapes.decode(String(describing: endpoint)))
        #expect(!pretty.localizedCaseInsensitiveContains("\\032"))
    }
}
