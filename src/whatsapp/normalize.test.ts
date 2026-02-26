import { describe, expect, it } from "vitest";

import { isWhatsAppGroupJid, isWhatsAppUserTarget, normalizeWhatsAppTarget } from "./normalize.js";

/**
 * normalizeWhatsAppTarget 函数的测试套件
 * 测试各种 WhatsApp 目标地址标准化场景
 */
describe("normalizeWhatsAppTarget", () => {
  /**
   * 测试用例：保留群组 JID 格式
   * 验证群组 JID 在标准化过程中保持不变
   */
  it("preserves group JIDs", () => {
    expect(normalizeWhatsAppTarget("120363401234567890@g.us")).toBe("120363401234567890@g.us");
    expect(normalizeWhatsAppTarget("123456789-987654321@g.us")).toBe("123456789-987654321@g.us");
    // 测试带 "whatsapp:" 前缀的群组 JID，前缀应该被正确移除
    expect(normalizeWhatsAppTarget("whatsapp:120363401234567890@g.us")).toBe(
      "120363401234567890@g.us",
    );
  });

  /**
   * 测试用例：将直接 JID 标准化为 E.164 格式
   * 验证简单的用户 JID 可以正确转换为国际电话号码格式
   */
  it("normalizes direct JIDs to E.164", () => {
    expect(normalizeWhatsAppTarget("1555123@s.whatsapp.net")).toBe("+1555123");
  });

  /**
   * 测试用例：带设备后缀的用户 JID 标准化为 E.164 格式
   * 这是 BUG 修复测试：JID 如 "41796666864:0@s.whatsapp.net" 应该
   * 标准化为 "+41796666864"，而不是 "+417966668640"（避免将 ":0" 错误地当作电话号码的一部分）
   */
  it("normalizes user JIDs with device suffix to E.164", () => {
    // 这是修复后的行为：设备后缀 :0 不会被错误地附加到电话号码
    expect(normalizeWhatsAppTarget("41796666864:0@s.whatsapp.net")).toBe("+41796666864");
    expect(normalizeWhatsAppTarget("1234567890:123@s.whatsapp.net")).toBe("+1234567890");
    // 不带设备后缀的情况仍然正常工作
    expect(normalizeWhatsAppTarget("41796666864@s.whatsapp.net")).toBe("+41796666864");
  });

  /**
   * 测试用例：将 LID JID 标准化为 E.164 格式
   * 验证 WhatsApp 的本地标识符（LID）格式可以正确转换为电话号码
   * LID 格式不区分大小写
   */
  it("normalizes LID JIDs to E.164", () => {
    expect(normalizeWhatsAppTarget("123456789@lid")).toBe("+123456789");
    expect(normalizeWhatsAppTarget("123456789@LID")).toBe("+123456789");
  });

  /**
   * 测试用例：拒绝无效的目标地址
   * 验证各种无效输入会被正确拒绝并返回 null
   */
  it("rejects invalid targets", () => {
    // 长度过短，无法构成有效的电话号码
    expect(normalizeWhatsAppTarget("wat")).toBeNull();
    // 空字符串或只有前缀
    expect(normalizeWhatsAppTarget("whatsapp:")).toBeNull();
    // 无效的群组 JID（没有群组 ID）
    expect(normalizeWhatsAppTarget("@g.us")).toBeNull();
    // 群组地址带有错误的 whatsapp: 前缀格式
    expect(normalizeWhatsAppTarget("whatsapp:group:@g.us")).toBeNull();
    expect(normalizeWhatsAppTarget("whatsapp:group:120363401234567890@g.us")).toBeNull();
    expect(normalizeWhatsAppTarget("group:123456789-987654321@g.us")).toBeNull();
    // 群组 JID 格式错误（首尾有空格，格式不正确）
    expect(normalizeWhatsAppTarget(" WhatsApp:Group:123456789-987654321@G.US ")).toBeNull();
    // 字母开头的 JID，无法解析为有效的电话号码
    expect(normalizeWhatsAppTarget("abc@s.whatsapp.net")).toBeNull();
  });

  /**
   * 测试用例：处理重复的前缀
   * 验证多个连续的 "whatsapp:" 前缀会被正确处理
   */
  it("handles repeated prefixes", () => {
    // 多个 "whatsapp:" 前缀应该被全部移除，只保留最终的电话号码
    expect(normalizeWhatsAppTarget("whatsapp:whatsapp:+1555")).toBe("+1555");
    // 但群组地址带有 "group:" 前缀会被拒绝（群组不能以这种方式指定）
    expect(normalizeWhatsAppTarget("group:group:120@g.us")).toBeNull();
  });
});

/**
 * isWhatsAppUserTarget 函数的测试套件
 * 测试各种用户目标地址格式的检测场景
 */
describe("isWhatsAppUserTarget", () => {
  /**
   * 测试用例：检测各种格式的用户 JID
   * 验证不同格式的用户标识符可以被正确识别
   */
  it("detects user JIDs with various formats", () => {
    // 标准用户 JID（带设备后缀）
    expect(isWhatsAppUserTarget("41796666864:0@s.whatsapp.net")).toBe(true);
    // 标准用户 JID（不带设备后缀）
    expect(isWhatsAppUserTarget("1234567890@s.whatsapp.net")).toBe(true);
    // LID 格式（小写）
    expect(isWhatsAppUserTarget("123456789@lid")).toBe(true);
    // LID 格式（大写）
    expect(isWhatsAppUserTarget("123456789@LID")).toBe(true);
    // 无效格式：LID 后面还有内容
    expect(isWhatsAppUserTarget("123@lid:0")).toBe(false);
    // 无效格式：字母开头的 JID，无法构成有效电话号码
    expect(isWhatsAppUserTarget("abc@s.whatsapp.net")).toBe(false);
    // 无效格式：这是群组 JID，不是用户 JID
    expect(isWhatsAppUserTarget("123456789-987654321@g.us")).toBe(false);
    // 无效格式：纯电话号码格式，不是完整的 JID
    expect(isWhatsAppUserTarget("+1555123")).toBe(false);
  });
});

/**
 * isWhatsAppGroupJid 函数的测试套件
 * 测试各种群组 JID 格式的检测场景
 */
describe("isWhatsAppGroupJid", () => {
  /**
   * 测试用例：检测带或不带前缀的群组 JID
   * 验证群组标识符可以被正确识别，同时排除非群组格式
   */
  it("detects group JIDs with or without prefixes", () => {
    // 有效的群组 JID（纯数字格式）
    expect(isWhatsAppGroupJid("120363401234567890@g.us")).toBe(true);
    // 有效的群组 JID（带连字符格式）
    expect(isWhatsAppGroupJid("123456789-987654321@g.us")).toBe(true);
    // 有效的群组 JID（带 "whatsapp:" 前缀）
    expect(isWhatsAppGroupJid("whatsapp:120363401234567890@g.us")).toBe(true);
    // 无效：群组 JID 不应该有 "group:" 前缀
    expect(isWhatsAppGroupJid("whatsapp:group:120363401234567890@g.us")).toBe(false);
    // 无效：本地部分太短（只有一个字符）
    expect(isWhatsAppGroupJid("x@g.us")).toBe(false);
    // 无效：本地部分为空
    expect(isWhatsAppGroupJid("@g.us")).toBe(false);
    // 无效：后缀不匹配（应该是 @g.us，不是 @g.usx）
    expect(isWhatsAppGroupJid("120@g.usx")).toBe(false);
    // 无效：这是电话号码格式，不是群组 JID
    expect(isWhatsAppGroupJid("+1555123")).toBe(false);
  });
});
