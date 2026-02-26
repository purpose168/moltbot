/**
 * 向导选择选项类型
 * @template T - 选项值的类型，默认为字符串
 */
export type WizardSelectOption<T = string> = {
  /** 选项的值 */
  value: T;
  /** 选项的显示标签 */
  label: string;
  /** 选项的提示信息 */
  hint?: string;
};

/**
 * 向导单选参数类型
 * @template T - 选项值的类型，默认为字符串
 */
export type WizardSelectParams<T = string> = {
  /** 提示消息 */
  message: string;
  /** 选项数组 */
  options: Array<WizardSelectOption<T>>;
  /** 初始值 */
  initialValue?: T;
};

/**
 * 向导多选参数类型
 * @template T - 选项值的类型，默认为字符串
 */
export type WizardMultiSelectParams<T = string> = {
  /** 提示消息 */
  message: string;
  /** 选项数组 */
  options: Array<WizardSelectOption<T>>;
  /** 初始值数组 */
  initialValues?: T[];
};

/**
 * 向导文本输入参数类型
 */
export type WizardTextParams = {
  /** 提示消息 */
  message: string;
  /** 初始值 */
  initialValue?: string;
  /** 占位符 */
  placeholder?: string;
  /** 验证函数，返回错误信息或 undefined */
  validate?: (value: string) => string | undefined;
};

/**
 * 向导确认参数类型
 */
export type WizardConfirmParams = {
  /** 提示消息 */
  message: string;
  /** 初始值 */
  initialValue?: boolean;
};

/**
 * 向导进度条类型
 */
export type WizardProgress = {
  /** 更新进度消息 */
  update: (message: string) => void;
  /** 停止进度条并显示完成消息 */
  stop: (message?: string) => void;
};

/**
 * 向导提示器类型
 */
export type WizardPrompter = {
  /** 显示向导介绍 */
  intro: (title: string) => Promise<void>;
  /** 显示向导结束信息 */
  outro: (message: string) => Promise<void>;
  /** 显示提示信息 */
  note: (message: string, title?: string) => Promise<void>;
  /** 显示单选菜单 */
  select: <T>(params: WizardSelectParams<T>) => Promise<T>;
  /** 显示多选菜单 */
  multiselect: <T>(params: WizardMultiSelectParams<T>) => Promise<T[]>;
  /** 显示文本输入框 */
  text: (params: WizardTextParams) => Promise<string>;
  /** 显示确认对话框 */
  confirm: (params: WizardConfirmParams) => Promise<boolean>;
  /** 创建进度条 */
  progress: (label: string) => WizardProgress;
};

/**
 * 向导取消错误类
 */
export class WizardCancelledError extends Error {
  constructor(message = "向导已取消") {
    super(message);
    this.name = "WizardCancelledError";
  }
}
