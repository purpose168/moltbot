import { randomUUID } from "node:crypto";

import { WizardCancelledError, type WizardProgress, type WizardPrompter } from "./prompts.js";

/**
 * 向导步骤选项类型
 */
export type WizardStepOption = {
  /** 选项的值 */
  value: unknown;
  /** 选项的显示标签 */
  label: string;
  /** 选项的提示信息 */
  hint?: string;
};

/**
 * 向导步骤类型
 */
export type WizardStep = {
  /** 步骤ID */
  id: string;
  /** 步骤类型 */
  type: "note" | "select" | "text" | "confirm" | "multiselect" | "progress" | "action";
  /** 步骤标题 */
  title?: string;
  /** 步骤消息 */
  message?: string;
  /** 步骤选项 */
  options?: WizardStepOption[];
  /** 初始值 */
  initialValue?: unknown;
  /** 占位符 */
  placeholder?: string;
  /** 是否敏感信息 */
  sensitive?: boolean;
  /** 执行器 */
  executor?: "gateway" | "client";
};

/**
 * 向导会话状态类型
 */
export type WizardSessionStatus = "running" | "done" | "cancelled" | "error";

/**
 * 向导下一步结果类型
 */
export type WizardNextResult = {
  /** 是否完成 */
  done: boolean;
  /** 下一步骤 */
  step?: WizardStep;
  /** 会话状态 */
  status: WizardSessionStatus;
  /** 错误信息 */
  error?: string;
};

/**
 * 延迟对象类型
 */
type Deferred<T> = {
  /** 承诺 */
  promise: Promise<T>;
  /** 解析函数 */
  resolve: (value: T) => void;
  /** 拒绝函数 */
  reject: (err: unknown) => void;
};

/**
 * 创建延迟对象
 */
function createDeferred<T>(): Deferred<T> {
  let resolve!: (value: T) => void;
  let reject!: (err: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

/**
 * 向导会话提示器类
 */
class WizardSessionPrompter implements WizardPrompter {
  constructor(private session: WizardSession) {}

  /**
   * 显示向导介绍
   */
  async intro(title: string): Promise<void> {
    await this.prompt({
      type: "note",
      title,
      message: "",
      executor: "client",
    });
  }

  /**
   * 显示向导结束信息
   */
  async outro(message: string): Promise<void> {
    await this.prompt({
      type: "note",
      title: "完成",
      message,
      executor: "client",
    });
  }

  /**
   * 显示提示信息
   */
  async note(message: string, title?: string): Promise<void> {
    await this.prompt({ type: "note", title, message, executor: "client" });
  }

  /**
   * 显示单选菜单
   */
  async select<T>(params: {
    message: string;
    options: Array<{ value: T; label: string; hint?: string }>;
    initialValue?: T;
  }): Promise<T> {
    const res = await this.prompt({
      type: "select",
      message: params.message,
      options: params.options.map((opt) => ({
        value: opt.value,
        label: opt.label,
        hint: opt.hint,
      })),
      initialValue: params.initialValue,
      executor: "client",
    });
    return res as T;
  }

  /**
   * 显示多选菜单
   */
  async multiselect<T>(params: {
    message: string;
    options: Array<{ value: T; label: string; hint?: string }>;
    initialValues?: T[];
  }): Promise<T[]> {
    const res = await this.prompt({
      type: "multiselect",
      message: params.message,
      options: params.options.map((opt) => ({
        value: opt.value,
        label: opt.label,
        hint: opt.hint,
      })),
      initialValue: params.initialValues,
      executor: "client",
    });
    return (Array.isArray(res) ? res : []) as T[];
  }

  /**
   * 显示文本输入框
   */
  async text(params: {
    message: string;
    initialValue?: string;
    placeholder?: string;
    validate?: (value: string) => string | undefined;
  }): Promise<string> {
    const res = await this.prompt({
      type: "text",
      message: params.message,
      initialValue: params.initialValue,
      placeholder: params.placeholder,
      executor: "client",
    });
    const value =
      res === null || res === undefined
        ? ""
        : typeof res === "string"
          ? res
          : typeof res === "number" || typeof res === "boolean" || typeof res === "bigint"
            ? String(res)
            : "";
    const error = params.validate?.(value);
    if (error) {
      throw new Error(error);
    }
    return value;
  }

  /**
   * 显示确认对话框
   */
  async confirm(params: { message: string; initialValue?: boolean }): Promise<boolean> {
    const res = await this.prompt({
      type: "confirm",
      message: params.message,
      initialValue: params.initialValue,
      executor: "client",
    });
    return Boolean(res);
  }

  /**
   * 创建进度条
   */
  progress(_label: string): WizardProgress {
    return {
      update: (_message) => {},
      stop: (_message) => {},
    };
  }

  /**
   * 提示步骤
   */
  private async prompt(step: Omit<WizardStep, "id">): Promise<unknown> {
    return await this.session.awaitAnswer({
      ...step,
      id: randomUUID(),
    });
  }
}

/**
 * 向导会话类
 */
export class WizardSession {
  /** 当前步骤 */
  private currentStep: WizardStep | null = null;
  /** 步骤延迟对象 */
  private stepDeferred: Deferred<WizardStep | null> | null = null;
  /** 回答延迟对象映射 */
  private answerDeferred = new Map<string, Deferred<unknown>>();
  /** 会话状态 */
  private status: WizardSessionStatus = "running";
  /** 错误信息 */
  private error: string | undefined;

  /**
   * 构造函数
   */
  constructor(private runner: (prompter: WizardPrompter) => Promise<void>) {
    const prompter = new WizardSessionPrompter(this);
    void this.run(prompter);
  }

  /**
   * 获取下一步骤
   */
  async next(): Promise<WizardNextResult> {
    if (this.currentStep) {
      return { done: false, step: this.currentStep, status: this.status };
    }
    if (this.status !== "running") {
      return { done: true, status: this.status, error: this.error };
    }
    if (!this.stepDeferred) {
      this.stepDeferred = createDeferred();
    }
    const step = await this.stepDeferred.promise;
    if (step) {
      return { done: false, step, status: this.status };
    }
    return { done: true, status: this.status, error: this.error };
  }

  /**
   * 回答步骤
   */
  async answer(stepId: string, value: unknown): Promise<void> {
    const deferred = this.answerDeferred.get(stepId);
    if (!deferred) {
      throw new Error("向导：没有待处理的步骤");
    }
    this.answerDeferred.delete(stepId);
    this.currentStep = null;
    deferred.resolve(value);
  }

  /**
   * 取消向导
   */
  cancel() {
    if (this.status !== "running") return;
    this.status = "cancelled";
    this.error = "已取消";
    this.currentStep = null;
    for (const [, deferred] of this.answerDeferred) {
      deferred.reject(new WizardCancelledError());
    }
    this.answerDeferred.clear();
    this.resolveStep(null);
  }

  /**
   * 推送步骤
   */
  pushStep(step: WizardStep) {
    this.currentStep = step;
    this.resolveStep(step);
  }

  /**
   * 运行向导
   */
  private async run(prompter: WizardPrompter) {
    try {
      await this.runner(prompter);
      this.status = "done";
    } catch (err) {
      if (err instanceof WizardCancelledError) {
        this.status = "cancelled";
        this.error = err.message;
      } else {
        this.status = "error";
        this.error = String(err);
      }
    } finally {
      this.resolveStep(null);
    }
  }

  /**
   * 等待回答
   */
  async awaitAnswer(step: WizardStep): Promise<unknown> {
    if (this.status !== "running") {
      throw new Error("向导：会话未运行");
    }
    this.pushStep(step);
    const deferred = createDeferred<unknown>();
    this.answerDeferred.set(step.id, deferred);
    return await deferred.promise;
  }

  /**
   * 解析步骤
   */
  private resolveStep(step: WizardStep | null) {
    if (!this.stepDeferred) return;
    const deferred = this.stepDeferred;
    this.stepDeferred = null;
    deferred.resolve(step);
  }

  /**
   * 获取会话状态
   */
  getStatus(): WizardSessionStatus {
    return this.status;
  }

  /**
   * 获取错误信息
   */
  getError(): string | undefined {
    return this.error;
  }
}
