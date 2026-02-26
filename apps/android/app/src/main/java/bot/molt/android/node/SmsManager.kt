package bot.molt.android.node

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.telephony.SmsManager as AndroidSmsManager
import androidx.core.content.ContextCompat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.encodeToString
import bot.molt.android.PermissionRequester

/**
 * 短信管理器
 * 通过Android短信API发送短信消息
 * 需要授予SEND_SMS权限
 */
class SmsManager(private val context: Context) {

    private val json = JsonConfig
    @Volatile private var permissionRequester: PermissionRequester? = null

    /**
     * 发送结果数据类
     * @param ok 是否成功
     * @param to 接收方号码
     * @param message 消息内容
     * @param error 错误信息
     * @param payloadJson 负载JSON字符串
     */
    data class SendResult(
        val ok: Boolean,
        val to: String,
        val message: String?,
        val error: String? = null,
        val payloadJson: String,
    )

    /**
     * 解析参数数据类
     * @param to 接收方号码
     * @param message 消息内容
     */
    internal data class ParsedParams(
        val to: String,
        val message: String,
    )

    /**
     * 解析结果密封类
     */
    internal sealed class ParseResult {
        /**
         * 成功解析结果
         * @param params 解析后的参数
         */
        data class Ok(val params: ParsedParams) : ParseResult()
        /**
         * 解析错误结果
         * @param error 错误信息
         * @param to 接收方号码
         * @param message 消息内容
         */
        data class Error(
            val error: String,
            val to: String = "",
            val message: String? = null,
        ) : ParseResult()
    }

    /**
     * 发送计划数据类
     * @param parts 消息部分列表
     * @param useMultipart 是否使用多部分发送
     */
    internal data class SendPlan(
        val parts: List<String>,
        val useMultipart: Boolean,
    )

    companion object {
        internal val JsonConfig = Json { ignoreUnknownKeys = true }

        /**
         * 解析参数
         * @param paramsJson 参数JSON字符串
         * @param json JSON配置
         * @return 解析结果
         */
        internal fun parseParams(paramsJson: String?, json: Json = JsonConfig): ParseResult {
            val params = paramsJson?.trim().orEmpty()
            if (params.isEmpty()) {
                return ParseResult.Error(error = "INVALID_REQUEST: 需要paramsJSON")
            }

            val obj = try {
                json.parseToJsonElement(params).jsonObject
            } catch (_: Throwable) {
                null
            }

            if (obj == null) {
                return ParseResult.Error(error = "INVALID_REQUEST: 期望JSON对象")
            }

            val to = (obj["to"] as? JsonPrimitive)?.content?.trim().orEmpty()
            val message = (obj["message"] as? JsonPrimitive)?.content.orEmpty()

            if (to.isEmpty()) {
                return ParseResult.Error(
                    error = "INVALID_REQUEST: 需要接收方电话号码",
                    message = message,
                )
            }

            if (message.isEmpty()) {
                return ParseResult.Error(
                    error = "INVALID_REQUEST: 需要消息文本",
                    to = to,
                )
            }

            return ParseResult.Ok(ParsedParams(to = to, message = message))
        }

        /**
         * 构建发送计划
         * @param message 消息内容
         * @param divider 分割函数
         * @return 发送计划
         */
        internal fun buildSendPlan(
            message: String,
            divider: (String) -> List<String>,
        ): SendPlan {
            val parts = divider(message).ifEmpty { listOf(message) }
            return SendPlan(parts = parts, useMultipart = parts.size > 1)
        }

        /**
         * 构建负载JSON
         * @param json JSON配置
         * @param ok 是否成功
         * @param to 接收方号码
         * @param error 错误信息
         * @return JSON字符串
         */
        internal fun buildPayloadJson(
            json: Json = JsonConfig,
            ok: Boolean,
            to: String,
            error: String?,
        ): String {
            val payload =
                mutableMapOf<String, JsonElement>(
                    "ok" to JsonPrimitive(ok),
                    "to" to JsonPrimitive(to),
                )
            if (!ok) {
                payload["error"] = JsonPrimitive(error ?: "SMS_SEND_FAILED")
            }
            return json.encodeToString(JsonObject.serializer(), JsonObject(payload))
        }
    }

    /**
     * 检查是否有短信权限
     */
    fun hasSmsPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * 检查是否可以发送短信
     */
    fun canSendSms(): Boolean {
        return hasSmsPermission() && hasTelephonyFeature()
    }

    /**
     * 检查是否有电话功能
     */
    fun hasTelephonyFeature(): Boolean {
        return context.packageManager?.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) == true
    }

    /**
     * 附加权限请求器
     */
    fun attachPermissionRequester(requester: PermissionRequester) {
        permissionRequester = requester
    }

    /**
     * 发送短信消息
     * @param paramsJson 包含"to"(电话号码)和"message"(文本)字段的JSON
     * @return 发送结果,指示成功或失败
     */
    suspend fun send(paramsJson: String?): SendResult {
        if (!hasTelephonyFeature()) {
            return errorResult(
                error = "SMS_UNAVAILABLE: 电话功能不可用",
            )
        }

        if (!ensureSmsPermission()) {
            return errorResult(
                error = "SMS_PERMISSION_REQUIRED: 请授予短信权限",
            )
        }

        val parseResult = parseParams(paramsJson, json)
        if (parseResult is ParseResult.Error) {
            return errorResult(
                error = parseResult.error,
                to = parseResult.to,
                message = parseResult.message,
            )
        }
        val params = (parseResult as ParseResult.Ok).params

        return try {
            val smsManager = context.getSystemService(AndroidSmsManager::class.java)
                ?: throw IllegalStateException("SMS_UNAVAILABLE: SmsManager不可用")

            val plan = buildSendPlan(params.message) { smsManager.divideMessage(it) }
            if (plan.useMultipart) {
                // 发送多部分短信
                smsManager.sendMultipartTextMessage(
                    params.to,     // 目标号码
                    null,          // 短信中心(null=默认)
                    ArrayList(plan.parts),    // 消息部分
                    null,          // 发送意图
                    null,          // 投递意图
                )
            } else {
                // 发送单条短信
                smsManager.sendTextMessage(
                    params.to,     // 目标号码
                    null,          // 短信中心(null=默认)
                    params.message,// 消息内容
                    null,          // 发送意图
                    null,          // 投递意图
                )
            }

            okResult(to = params.to, message = params.message)
        } catch (e: SecurityException) {
            errorResult(
                error = "SMS_PERMISSION_REQUIRED: ${e.message}",
                to = params.to,
                message = params.message,
            )
        } catch (e: Throwable) {
            errorResult(
                error = "SMS_SEND_FAILED: ${e.message ?: "未知错误"}",
                to = params.to,
                message = params.message,
            )
        }
    }

    /**
     * 确保有短信权限
     */
    private suspend fun ensureSmsPermission(): Boolean {
        if (hasSmsPermission()) return true
        val requester = permissionRequester ?: return false
        val results = requester.requestIfMissing(listOf(Manifest.permission.SEND_SMS))
        return results[Manifest.permission.SEND_SMS] == true
    }

    /**
     * 创建成功结果
     */
    private fun okResult(to: String, message: String): SendResult {
        return SendResult(
            ok = true,
            to = to,
            message = message,
            error = null,
            payloadJson = buildPayloadJson(json = json, ok = true, to = to, error = null),
        )
    }

    /**
     * 创建错误结果
     */
    private fun errorResult(error: String, to: String = "", message: String? = null): SendResult {
        return SendResult(
            ok = false,
            to = to,
            message = message,
            error = error,
            payloadJson = buildPayloadJson(json = json, ok = false, to = to, error = error),
        )
    }
}
