import { useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { KeyRound, Save } from "lucide-react";
import { toast } from "sonner";

import { api, describeError } from "../../lib/api";
import { useAuthStore } from "../../stores/auth";
import { Button } from "../ui/button";
import { Card, CardContent, CardFooter, CardHeader } from "../ui/card";
import { Field } from "../ui/field";
import { Input } from "../ui/input";

export function PasswordCard() {
  const username = useAuthStore((state) => state.username);
  const [name, setName] = useState(username ?? "admin");
  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirm, setConfirm] = useState("");

  const save = useMutation({
    mutationFn: () => api.changePassword(name.trim(), oldPassword, newPassword),
    onSuccess: () => {
      toast.success("管理员密码已修改，请使用新密码重新登录");
      setOldPassword("");
      setNewPassword("");
      setConfirm("");
      useAuthStore.getState().clear();
    },
    onError: (error) => toast.error(describeError(error)),
  });

  const valid =
    name.trim().length > 0 &&
    oldPassword.length > 0 &&
    newPassword.length >= 4 &&
    newPassword === confirm;

  return (
    <Card className="flex flex-col">
      <CardHeader
        title="管理员凭据"
        description="修改管理员账号与密码，保存后所有已有会话会立即失效。"
        actions={<KeyRound className="h-4 w-4 text-text-3" />}
      />
      <CardContent className="flex flex-1 flex-col gap-3 pt-2">
        <Field label="管理员账号">
          <Input
            value={name}
            autoComplete="username"
            onChange={(event) => setName(event.target.value)}
          />
        </Field>
        <Field label="当前密码">
          <Input
            type="password"
            value={oldPassword}
            autoComplete="current-password"
            placeholder="输入当前管理员密码"
            onChange={(event) => setOldPassword(event.target.value)}
          />
        </Field>
        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="新密码" hint="至少 4 位字符">
            <Input
              type="password"
              value={newPassword}
              autoComplete="new-password"
              onChange={(event) => setNewPassword(event.target.value)}
            />
          </Field>
          <Field
            label="确认新密码"
            hint={confirm && confirm !== newPassword ? "两次输入不一致" : undefined}
          >
            <Input
              type="password"
              value={confirm}
              autoComplete="new-password"
              onChange={(event) => setConfirm(event.target.value)}
            />
          </Field>
        </div>
        <p className="text-[10.5px] leading-4 text-text-3">
          修改成功后当前页面会退出登录，需要使用新密码重新进入管理页。
        </p>
      </CardContent>
      <CardFooter>
        <span className="text-[10.5px] text-text-3">
          {newPassword && confirm && newPassword !== confirm
            ? "两次输入的新密码不一致"
            : "密码不会以明文保存"}
        </span>
        <Button
          size="sm"
          variant="primary"
          disabled={!valid}
          loading={save.isPending}
          onClick={() => save.mutate()}
        >
          <Save className="h-3.5 w-3.5" />
          修改密码
        </Button>
      </CardFooter>
    </Card>
  );
}
