import { Component, type ErrorInfo, type ReactNode } from "react";

import { Button } from "./ui/button";

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error("界面渲染失败", error, info.componentStack);
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="flex h-full items-center justify-center bg-bg p-8">
        <div className="w-full max-w-[420px] rounded-2xl border border-border bg-surface p-6 text-center shadow-[var(--shadow-card)]">
          <h1 className="text-[16px] font-semibold text-text">界面加载失败</h1>
          <p className="mt-2 text-[12.5px] leading-5 text-text-3">
            {this.state.error.message || "发生了未预期的错误，请重新加载界面。"}
          </p>
          <Button className="mt-5" variant="primary" onClick={() => window.location.reload()}>
            重新加载
          </Button>
        </div>
      </div>
    );
  }
}
