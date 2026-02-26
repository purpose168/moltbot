package bot.molt.android.chat

/**
 * 聊天消息数据类
 * @param id 消息ID
 * @param role 角色(user/assistant)
 * @param content 消息内容列表
 * @param timestampMs 时间戳(毫秒)
 */
data class ChatMessage(
  val id: String,
  val role: String,
  val content: List<ChatMessageContent>,
  val timestampMs: Long?,
)

/**
 * 聊天消息内容数据类
 * @param type 内容类型(text/image等)
 * @param text 文本内容(仅当type为text时)
 * @param mimeType MIME类型(仅当type为image等时)
 * @param fileName 文件名(仅当type为image等时)
 * @param base64 Base64编码的内容(仅当type为image等时)
 */
data class ChatMessageContent(
  val type: String = "text",
  val text: String? = null,
  val mimeType: String? = null,
  val fileName: String? = null,
  val base64: String? = null,
)

/**
 * 聊天待处理工具调用数据类
 * @param toolCallId 工具调用ID
 * @param name 工具名称
 * @param args 工具参数(JSON对象)
 * @param startedAtMs 开始时间(毫秒)
 * @param isError 是否为错误
 */
data class ChatPendingToolCall(
  val toolCallId: String,
  val name: String,
  val args: kotlinx.serialization.json.JsonObject? = null,
  val startedAtMs: Long,
  val isError: Boolean? = null,
)

/**
 * 聊天会话条目数据类
 * @param key 会话密钥
 * @param updatedAtMs 更新时间(毫秒)
 * @param displayName 显示名称
 */
data class ChatSessionEntry(
  val key: String,
  val updatedAtMs: Long?,
  val displayName: String? = null,
)

/**
 * 聊天历史数据类
 * @param sessionKey 会话密钥
 * @param sessionId 会话ID
 * @param thinkingLevel 思考级别
 * @param messages 消息列表
 */
data class ChatHistory(
  val sessionKey: String,
  val sessionId: String?,
  val thinkingLevel: String?,
  val messages: List<ChatMessage>,
)

/**
 * 发出附件数据类
 * @param type 附件类型
 * @param mimeType MIME类型
 * @param fileName 文件名
 * @param base64 Base64编码的内容
 */
data class OutgoingAttachment(
  val type: String,
  val mimeType: String,
  val fileName: String,
  val base64: String,
)
