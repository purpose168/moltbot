package bot.molt.android.gateway

import android.content.Context
import android.util.Base64
import java.io.File
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.PKCS8EncodedKeySpec
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * 设备身份数据类
 * @param deviceId 设备ID
 * @param publicKeyRawBase64 Base64编码的公钥
 * @param privateKeyPkcs8Base64 Base64编码的PKCS8私钥
 * @param createdAtMs 创建时间(毫秒)
 */
@Serializable
data class DeviceIdentity(
  val deviceId: String,
  val publicKeyRawBase64: String,
  val privateKeyPkcs8Base64: String,
  val createdAtMs: Long,
)

/**
 * 设备身份存储类
 * 负责管理设备身份的存储、加载和签名
 */
class DeviceIdentityStore(context: Context) {
  private val json = Json { ignoreUnknownKeys = true }
  private val identityFile = File(context.filesDir, "moltbot/identity/device.json")

  /**
   * 加载或创建设备身份
   */
  @Synchronized
  fun loadOrCreate(): DeviceIdentity {
    val existing = load()
    if (existing != null) {
      val derived = deriveDeviceId(existing.publicKeyRawBase64)
      if (derived != null && derived != existing.deviceId) {
        val updated = existing.copy(deviceId = derived)
        save(updated)
        return updated
      }
      return existing
    }
    val fresh = generate()
    save(fresh)
    return fresh
  }

  /**
   * 签名负载
   * @param payload 负载字符串
   * @param identity 设备身份
   * @return Base64 URL编码的签名,失败则返回null
   */
  fun signPayload(payload: String, identity: DeviceIdentity): String? {
    return try {
      val privateKeyBytes = Base64.decode(identity.privateKeyPkcs8Base64, Base64.DEFAULT)
      val keySpec = PKCS8EncodedKeySpec(privateKeyBytes)
      val keyFactory = KeyFactory.getInstance("Ed25519")
      val privateKey = keyFactory.generatePrivate(keySpec)
      val signature = Signature.getInstance("Ed25519")
      signature.initSign(privateKey)
      signature.update(payload.toByteArray(Charsets.UTF_8))
      base64UrlEncode(signature.sign())
    } catch (_: Throwable) {
      null
    }
  }

  /**
   * 获取Base64 URL编码的公钥
   * @param identity 设备身份
   * @return Base64 URL编码的公钥,失败则返回null
   */
  fun publicKeyBase64Url(identity: DeviceIdentity): String? {
    return try {
      val raw = Base64.decode(identity.publicKeyRawBase64, Base64.DEFAULT)
      base64UrlEncode(raw)
    } catch (_: Throwable) {
      null
    }
  }

  /**
   * 加载设备身份
   */
  private fun load(): DeviceIdentity? {
    return try {
      if (!identityFile.exists()) return null
      val raw = identityFile.readText(Charsets.UTF_8)
      val decoded = json.decodeFromString(DeviceIdentity.serializer(), raw)
      if (decoded.deviceId.isBlank() ||
        decoded.publicKeyRawBase64.isBlank() ||
        decoded.privateKeyPkcs8Base64.isBlank()
      ) {
        null
      } else {
        decoded
      }
    } catch (_: Throwable) {
      null
    }
  }

  /**
   * 保存设备身份
   */
  private fun save(identity: DeviceIdentity) {
    try {
      identityFile.parentFile?.mkdirs()
      val encoded = json.encodeToString(DeviceIdentity.serializer(), identity)
      identityFile.writeText(encoded, Charsets.UTF_8)
    } catch (_: Throwable) {
      // 仅尽力而为
    }
  }

  /**
   * 生成新的设备身份
   */
  private fun generate(): DeviceIdentity {
    val keyPair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
    val spki = keyPair.public.encoded
    val rawPublic = stripSpkiPrefix(spki)
    val deviceId = sha256Hex(rawPublic)
    val privateKey = keyPair.private.encoded
    return DeviceIdentity(
      deviceId = deviceId,
      publicKeyRawBase64 = Base64.encodeToString(rawPublic, Base64.NO_WRAP),
      privateKeyPkcs8Base64 = Base64.encodeToString(privateKey, Base64.NO_WRAP),
      createdAtMs = System.currentTimeMillis(),
    )
  }

  /**
   * 从公钥派生设备ID
   */
  private fun deriveDeviceId(publicKeyRawBase64: String): String? {
    return try {
      val raw = Base64.decode(publicKeyRawBase64, Base64.DEFAULT)
      sha256Hex(raw)
    } catch (_: Throwable) {
      null
    }
  }

  /**
   * 去除SPKI前缀
   */
  private fun stripSpkiPrefix(spki: ByteArray): ByteArray {
    if (spki.size == ED25519_SPKI_PREFIX.size + 32 &&
      spki.copyOfRange(0, ED25519_SPKI_PREFIX.size).contentEquals(ED25519_SPKI_PREFIX)
    ) {
      return spki.copyOfRange(ED25519_SPKI_PREFIX.size, spki.size)
    }
    return spki
  }

  /**
   * 计算SHA-256哈希
   */
  private fun sha256Hex(data: ByteArray): String {
    val digest = MessageDigest.getInstance("SHA-256").digest(data)
    val out = StringBuilder(digest.size * 2)
    for (byte in digest) {
      out.append(String.format("%02x", byte))
    }
    return out.toString()
  }

  /**
   * Base64 URL编码
   */
  private fun base64UrlEncode(data: ByteArray): String {
    return Base64.encodeToString(data, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
  }

  companion object {
    private val ED25519_SPKI_PREFIX =
      byteArrayOf(
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
      )
  }
}
